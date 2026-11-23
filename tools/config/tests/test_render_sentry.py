import json
import re
import sys
import unittest
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import render_sentry  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
SENTRY = ROOT / "deploy" / "platform" / "sentry"
CFG = yaml.safe_load((ROOT / "config" / "platform.yaml").read_text(encoding="utf-8"))
OUT = render_sentry.render(CFG)
SECRET = yaml.safe_load(OUT[render_sentry.OUT])
VALUES = yaml.safe_load((SENTRY / "values.yaml").read_text(encoding="utf-8"))
CLICKHOUSE = yaml.safe_load((SENTRY / "clickhouse-values.yaml").read_text(encoding="utf-8"))


class RenderSentryTest(unittest.TestCase):
    def test_committed_file_is_current(self):
        for path, text in OUT.items():
            self.assertEqual(path.read_text(encoding="utf-8"), text, f"run tools/config/render_sentry.py: {path}")

    def test_names_follow_the_secrets_manager_convention(self):
        prefix = CFG["naming"]["prefix"]
        for item in SECRET["spec"]["data"]:
            self.assertRegex(item["remoteRef"]["key"], rf"^{re.escape(prefix)}/shared-services/sentry/[a-z-]+$")

    def test_every_secret_key_the_values_read_is_provided(self):
        provided = {d["secretKey"] for d in SECRET["spec"]["data"]}
        used = {
            VALUES["user"]["existingSecretKey"], VALUES["sentry"]["existingSecretKey"], VALUES["launchpadTaskWorker"]["existingSecretKey"],
            VALUES["externalClickhouse"]["existingSecretKey"], VALUES["redis"]["auth"]["existingSecretPasswordKey"],
            CLICKHOUSE["auth"]["existingSecretKey"], *VALUES["postgresql"]["auth"]["secretKeys"].values(),
        }
        self.assertLessEqual(used, provided)
        for ref in (VALUES["user"], VALUES["sentry"], VALUES["postgresql"]["auth"], VALUES["redis"]["auth"], VALUES["externalClickhouse"]):
            self.assertEqual(ref["existingSecret"], SECRET["metadata"]["name"])

    def test_no_password_in_the_values(self):
        text = (SENTRY / "values.yaml").read_text(encoding="utf-8")
        self.assertNotRegex(text, r"(?im)^\s*(password|secretKey):\s*\S")

    def test_stateless_tiers_run_two_replicas(self):
        self.assertGreaterEqual(VALUES["sentry"]["web"]["replicas"], 2)
        self.assertGreaterEqual(VALUES["relay"]["replicas"], 2)
        for worker in VALUES["sentry"]["taskWorker"]["workers"]:
            self.assertGreaterEqual(worker["replicas"], 2)

    def test_databases_are_replicated_and_persistent(self):
        self.assertEqual(VALUES["postgresql"]["architecture"], "replication")
        self.assertGreaterEqual(VALUES["redis"]["replica"]["replicaCount"], 2)
        self.assertGreaterEqual(VALUES["kafka"]["controller"]["replicaCount"], 3)
        self.assertGreaterEqual(CLICKHOUSE["replicaCount"], 2)
        self.assertTrue(VALUES["redis"]["master"]["persistence"]["enabled"])

    def test_session_replay_is_off(self):
        self.assertFalse(VALUES["sentry"]["features"]["enableSessionReplay"])

    def test_scrubbing_rules_mask_card_numbers_and_leave_other_text(self):
        config = json.loads((SENTRY / "pii-config.json").read_text(encoding="utf-8"))
        pan = re.compile(config["rules"]["pan"]["pattern"])
        self.assertTrue(pan.search("card 4111 1111 1111 1111 declined"))
        self.assertTrue(pan.search("pan=5500-0000-0000-0004"))
        self.assertFalse(pan.search("order 12345678 at 10:15"))
        self.assertIn("@creditcard:replace", config["applications"]["$string"])
        for rule in config["applications"]["$string"]:
            self.assertTrue(rule.startswith("@") or rule in config["rules"])


if __name__ == "__main__":
    unittest.main()
