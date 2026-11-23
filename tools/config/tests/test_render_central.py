import sys
import unittest
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import render_central  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
CFG = yaml.safe_load((ROOT / "config" / "platform.yaml").read_text(encoding="utf-8"))
OUT = render_central.render(CFG)
VALUES = yaml.safe_load(OUT[render_central.OUT / "values.yaml"])
SECRET = yaml.safe_load(OUT[render_central.OUT / "manifests" / "externalsecret.yaml"])


class RenderCentralTest(unittest.TestCase):
    def test_committed_files_are_current(self):
        for path, text in OUT.items():
            self.assertEqual(path.read_text(encoding="utf-8"), text, f"run tools/config/render_central.py: {path}")

    def test_three_replicas_that_gossip_and_survive_a_node_drain(self):
        self.assertEqual(VALUES["replicaCount"], 3)
        self.assertEqual(VALUES["podAntiAffinity"], "hard")
        self.assertEqual(VALUES["podDisruptionBudget"]["minAvailable"], 2)
        self.assertTrue(VALUES["persistence"]["enabled"])

    def test_the_config_is_the_one_under_observability(self):
        source = yaml.safe_load((render_central.SRC / "alertmanager.yaml").read_text(encoding="utf-8"))
        self.assertEqual(VALUES["config"]["route"], source["route"])
        self.assertEqual(VALUES["config"]["receivers"], source["receivers"])
        self.assertIn("notifications.tmpl", VALUES["templates"])

    def test_every_alert_goes_to_slack(self):
        for receiver in VALUES["config"]["receivers"]:
            if receiver["name"] != "deadmans-switch":
                self.assertIn("slack_configs", receiver, receiver["name"])
                self.assertNotIn("pagerduty_configs", receiver)

    def test_every_secret_file_of_the_config_is_provided(self):
        wanted = set(render_central.secret_files(VALUES["config"]))
        provided = {d["secretKey"] for d in SECRET["spec"]["data"]}
        self.assertEqual(wanted, provided)
        self.assertTrue({"slack-payments-alerts", "slack-payments-critical", "slack-security"} <= provided)

    def test_secret_names_follow_the_prefix(self):
        prefix = CFG["naming"]["prefix"]
        for d in SECRET["spec"]["data"]:
            self.assertTrue(d["remoteRef"]["key"].startswith(f"{prefix}/shared-services/alertmanager/"))


if __name__ == "__main__":
    unittest.main()
