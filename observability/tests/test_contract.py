import json
import re
import subprocess
import sys
import unittest
from pathlib import Path

import yaml

OBS = Path(__file__).resolve().parents[1]
REPO = OBS.parent
sys.path.insert(0, str(OBS / "coverage"))
sys.path.insert(0, str(OBS / "lib"))
import alert_coverage as cov  # noqa: E402
import thresholds  # noqa: E402

ALERTS, RECORDED = cov.load_rules([OBS / "alerts", OBS / "slo" / "generated"])
CATALOG = cov.load_catalog(OBS / "coverage" / "catalog")
TESTS = [yaml.safe_load(p.read_text()) for p in sorted((OBS / "tests").rglob("*.test.yaml"))]
SEVERITIES = {"critical", "warning", "security", "none"}
FORBIDDEN_LABELS = re.compile(r"\b(payment_id|customer_id|merchant_id|card|pan|cvv|token)\b")
HEADINGS = ["## Symptom", "## Diagnostics", "## Actions", "## Escalation", "## SSM document"]


def kebab(name):
    return re.sub(r"(?<=[a-z0-9])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])", "-", name).lower()


def test_cases():
    cases = {}
    for doc in TESTS:
        for t in doc["tests"]:
            for a in t.get("alert_rule_test", []):
                cases.setdefault(a["alertname"], []).append(bool(a["exp_alerts"]))
    return cases


class AlertContractTest(unittest.TestCase):
    def test_labels_and_annotations(self):
        for name, rule in ALERTS.items():
            with self.subTest(alert=name):
                for key in ("severity", "team", "service", "owner", "layer", "failure_mode"):
                    self.assertIn(key, rule["labels"])
                for key in ("summary", "runbook_url", "dashboard_url"):
                    self.assertIn(key, rule["annotations"])
                self.assertIn(rule["labels"]["severity"], SEVERITIES)

    def test_runbooks_exist_with_diagnostics(self):
        for name, rule in ALERTS.items():
            url = rule["annotations"]["runbook_url"]
            path = cov.runbook_path(url, REPO)
            with self.subTest(alert=name):
                self.assertIsNotNone(path, url)
                self.assertTrue(path.is_file(), url)
                text = path.read_text()
                if "#" in url:
                    self.assertIn(f"\n## {url.split('#')[1]}\n", text)
                else:
                    for heading in HEADINGS:
                        self.assertIn(heading, text)
                    self.assertIn("pay-runbook-", text)

    def test_every_alert_has_fire_and_quiet_tests(self):
        cases = test_cases()
        for name in ALERTS:
            with self.subTest(alert=name):
                self.assertIn(name, cases)
                self.assertIn(True, cases[name], "no test where the alert fires")
                if name != "Watchdog":
                    self.assertIn(False, cases[name], "no test where the alert stays silent")

    def test_slo_alerts_are_covered_per_window(self):
        for name in [n for n, r in ALERTS.items() if "slo" in r["labels"]]:
            self.assertIn(name, test_cases(), name)

    def test_failure_modes_and_catalog_agree(self):
        ids = [m["id"] for m in CATALOG]
        self.assertEqual(len(ids), len(set(ids)))
        for name, rule in ALERTS.items():
            self.assertIn(rule["labels"]["failure_mode"], ids, name)
        for mode in CATALOG:
            if mode.get("alert"):
                self.assertIn(mode["alert"], ALERTS, mode["id"])
                self.assertIn("detect_within", mode)

    def test_alert_names_are_unique(self):
        seen = []
        for path in sorted((OBS / "alerts").rglob("*.yaml")) + sorted((OBS / "slo" / "generated").glob("*.yaml")):
            for group in yaml.safe_load(path.read_text())["spec"]["groups"]:
                seen += [r["alert"] for r in group["rules"] if "alert" in r]
        self.assertEqual(len(seen), len(set(seen)))

    def test_dashboard_links_resolve(self):
        uids = {json.loads(p.read_text())["uid"] for p in (OBS / "dashboards").rglob("*.json")}
        for name, rule in ALERTS.items():
            self.assertIn(rule["annotations"]["dashboard_url"].rsplit("/", 1)[1], uids, name)

    def test_no_high_cardinality_or_card_labels(self):
        for name, rule in ALERTS.items():
            text = rule["expr"] + " " + " ".join(rule["labels"])
            self.assertIsNone(FORBIDDEN_LABELS.search(text), name)

    def test_cardinality_allowlist_forbids_the_same_labels(self):
        labels = yaml.safe_load((OBS / "standards" / "labels.yaml").read_text())
        for word in ("payment_id", "customer_id", "token", "pan", "cvv"):
            self.assertIn(word, labels["forbidden"])

    def test_generated_files_are_current(self):
        for script in ("slo/generate.py", "lib/gen_resilience.py", "lib/build.py"):
            res = subprocess.run([sys.executable, str(OBS / script), "--check"], capture_output=True, text=True)
            self.assertEqual(res.returncode, 0, res.stderr)

    def test_no_withdrawn_region_anywhere(self):
        for root in (OBS, REPO / "docs" / "runbooks", REPO / "policy" / "resilience"):
            for path in root.rglob("*"):
                if path.is_file() and path.suffix in (".yaml", ".md", ".json", ".py", ".tmpl") and path.name != "test_contract.py":
                    self.assertNotIn("eu-west-1", path.read_text(), str(path))

    def test_slo_burn_windows_follow_section_7(self):
        auth = [r for n, r in ALERTS.items() if n.startswith("PaymentsAuthorizationAvailability")]
        exprs = {n: r["expr"] for n, r in ALERTS.items() if n.startswith("PaymentsAuthorizationAvailability")}
        self.assertEqual(len(auth), 4)
        self.assertIn("(50 * 0.0001)", exprs["PaymentsAuthorizationAvailabilityBurnFastest"])
        self.assertIn("ratio_rate5m", exprs["PaymentsAuthorizationAvailabilityBurnFastest"])
        self.assertIn("(14.4 * 0.0001)", exprs["PaymentsAuthorizationAvailabilityBurnFast"])
        self.assertIn("(6 * 0.0001)", exprs["PaymentsAuthorizationAvailabilityBurnSlow"])
        self.assertIn("ratio_rate3d", exprs["PaymentsAuthorizationAvailabilityBurnTicket"])
        self.assertFalse([n for n in ALERTS if n.startswith("PaymentsStatusRead") and n.endswith("BurnFastest")])

    def test_threshold_constants_match_alert_expressions(self):
        for alert, const in thresholds.ALERT_LINKS.items():
            value = getattr(thresholds, const)
            self.assertIn(f"{value:g}", ALERTS[alert]["expr"].replace("10 * 1024 ^ 3", ""), f"{alert} vs {const}")

    def test_owner_decisions(self):
        a = ALERTS
        self.assertIn("> 300", a["LatestRestorableTimeLagHigh"]["expr"])
        self.assertEqual(a["LatestRestorableTimeLagHigh"]["for"], "10m")
        self.assertEqual(a["LatestRestorableTimeLagHigh"]["labels"]["severity"], "critical")
        self.assertIn("0.8 * ", a["RestoreDurationNearTarget"]["expr"])
        self.assertIn("backup_restore_target_seconds", a["RestoreDurationNearTarget"]["expr"])
        self.assertIn("> 5000", a["AuroraGlobalLagHigh"]["expr"])
        self.assertIn("> 10000", a["AuroraGlobalLagRpoBudgetExceeded"]["expr"])
        self.assertIn("< 0.75", a["CacheWarmRatioLow"]["expr"])
        self.assertEqual(a["CacheWarmRatioLow"]["for"], "5m")
        self.assertEqual(a["CacheWarmRatioLow"]["labels"]["severity"], "warning")
        self.assertIn("100 * 86400", a["DrSwitchTestOverdue"]["expr"])
        self.assertIn("region", a["DrSwitchTestOverdue"]["expr"])

    def test_paging_runbooks_name_their_ssm_document(self):
        for name, rule in ALERTS.items():
            if rule["labels"]["severity"] in ("critical", "security") and "slo" not in rule["labels"]:
                text = cov.runbook_path(rule["annotations"]["runbook_url"], REPO).read_text()
                self.assertIn(f"`pay-runbook-{kebab(name)}`", text, name)


if __name__ == "__main__":
    unittest.main()
