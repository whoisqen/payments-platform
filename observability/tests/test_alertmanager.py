import re
import sys
import unittest
from pathlib import Path

import yaml

OBS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(OBS / "coverage"))
import alert_coverage as cov  # noqa: E402

CONFIG = yaml.safe_load((OBS / "alertmanager" / "alertmanager.yaml").read_text())
ALERTS, _ = cov.load_rules([OBS / "alerts", OBS / "slo" / "generated"])
# Prometheus adds its external labels to every alert it sends
IMPLICIT = {"env", "region", "alertname"}


def firing_labels():
    out = {}
    for path in (OBS / "tests").rglob("*.test.yaml"):
        for t in yaml.safe_load(path.read_text())["tests"]:
            for a in t.get("alert_rule_test", []):
                for exp in a["exp_alerts"]:
                    out.setdefault(a["alertname"], {**exp["exp_labels"], "alertname": a["alertname"]})
    return out


LABELS = firing_labels()


def matches(matchers, labels):
    for m in matchers:
        key, op, val = re.fullmatch(r'([a-zA-Z_]\w*)(=~|!~|!=|=)"?(.*?)"?', m).groups()
        have = labels.get(key, "")
        ok = {"=": have == val, "!=": have != val, "=~": re.fullmatch(val, have) is not None, "!~": re.fullmatch(val, have) is None}[op]
        if not ok:
            return False
    return True


def route(labels, node=None):
    node = node or CONFIG["route"]
    for child in node.get("routes", []):
        if matches(child.get("matchers", []), labels):
            return route(labels, child)
    return node["receiver"]


def inhibited(rule, source, target):
    return matches(rule["source_matchers"], source) and matches(rule["target_matchers"], target) and all(source.get(k, "") == target.get(k, "") for k in rule["equal"])


class RoutingTest(unittest.TestCase):
    def test_every_alert_reaches_the_documented_receiver(self):
        for name, labels in LABELS.items():
            sev, team = labels["severity"], labels["team"]
            expected = {"security": "slack-security", "warning": "slack-payments-alerts", "critical": "slack-payments-critical", "none": "deadmans-switch" if name == "Watchdog" else "slack-payments-alerts"}.get(sev, "slack-payments-critical")
            if team == "security" and name != "Watchdog":
                expected = "slack-security"  # the team route comes before the severity routes
            with self.subTest(alert=name):
                self.assertEqual(route(labels), expected)

    def test_documented_examples(self):
        self.assertEqual(route({"severity": "critical", "team": "payments-core"}), "slack-payments-critical")
        self.assertEqual(route({"severity": "warning", "team": "payments-core"}), "slack-payments-alerts")
        self.assertEqual(route({"severity": "security", "team": "security"}), "slack-security")
        self.assertEqual(route({"alertname": "Watchdog", "severity": "none"}), "deadmans-switch")

    def test_cache_warm_alert_never_pages(self):
        self.assertEqual(route(LABELS["CacheWarmRatioLow"]), "slack-payments-alerts")

    def test_grouping_and_timers(self):
        root = CONFIG["route"]
        self.assertEqual(root["group_by"], ["alertname", "region", "psp"])
        self.assertEqual(root["group_wait"], "30s")
        critical = next(r for r in root["routes"] if r.get("matchers") == ['severity="critical"'])
        self.assertEqual(critical["repeat_interval"], "8760h")

    def test_receivers_exist_and_use_secret_files_only(self):
        names = {r["name"] for r in CONFIG["receivers"]}

        def walk(node):
            yield node["receiver"]
            for child in node.get("routes", []):
                yield from walk(child)
        self.assertLessEqual(set(walk(CONFIG["route"])), names)
        text = (OBS / "alertmanager" / "alertmanager.yaml").read_text()
        for plain in ("routing_key:", "api_url:", "service_key:", "  url:"):
            self.assertNotIn(plain, text)
        self.assertIn("api_url_file:", text)
        self.assertNotIn("routing_key", text)

    def test_templates_referenced_by_the_config_are_defined(self):
        used = set(re.findall(r'template "([\w.]+)"', (OBS / "alertmanager" / "alertmanager.yaml").read_text()))
        defined = set(re.findall(r'define "([\w.]+)"', (OBS / "alertmanager" / "templates" / "notifications.tmpl").read_text()))
        self.assertLessEqual(used, defined)


class InhibitionTest(unittest.TestCase):
    def test_equal_labels_exist_on_both_sides(self):
        for rule in CONFIG["inhibit_rules"]:
            sources = [n for n, lab in LABELS.items() if matches(rule["source_matchers"], lab)]
            targets = [n for n, lab in LABELS.items() if matches(rule["target_matchers"], lab) and n not in sources]
            self.assertTrue(sources, f"no alert matches the source of {rule}")
            self.assertTrue(targets, f"no alert matches the target of {rule}")
            for label in rule["equal"]:
                for name in sources + targets:
                    self.assertTrue(label in LABELS[name] or label in IMPLICIT, f"{name} lacks {label}: the rule {rule['equal']} would never inhibit")

    def test_region_down_silences_components_but_never_security(self):
        rule = CONFIG["inhibit_rules"][0]
        source = {"alertname": "RegionDown", "region": "eu-central-1", "severity": "critical"}
        self.assertTrue(inhibited(rule, source, {"alertname": "DrainLagHigh", "region": "eu-central-1", "severity": "critical"}))
        self.assertFalse(inhibited(rule, source, {"alertname": "RootAccountLogin", "region": "eu-central-1", "severity": "security"}))
        self.assertFalse(inhibited(rule, source, {"alertname": "AuroraGlobalLagHigh", "region": "us-east-1", "severity": "critical"}))

    def test_psp_degraded_silences_only_its_own_psp(self):
        rule = CONFIG["inhibit_rules"][1]
        source = {"alertname": "PSPDegraded", "psp": "acme"}
        self.assertTrue(inhibited(rule, source, {"alertname": "AuthorizationRateDrop", "psp": "acme"}))
        self.assertFalse(inhibited(rule, source, {"alertname": "AuthorizationRateDrop", "psp": "other"}))

    def test_burn_inhibition_stays_within_one_slo(self):
        rules = [r for r in CONFIG["inhibit_rules"] if r["equal"] == ["slo"]]

        def any_inhibits(source, target):
            return any(inhibited(r, source, target) for r in rules)

        fast = {"alertname": "PaymentsStatusReadBurnFast", "slo": "payments-status-read"}
        self.assertTrue(any_inhibits(fast, {"alertname": "PaymentsStatusReadBurnTicket", "slo": "payments-status-read"}))
        self.assertFalse(any_inhibits(fast, {"alertname": "PaymentsWebhookDeliveryBurnTicket", "slo": "payments-webhooks-delivery"}))

    def test_the_fastest_window_silences_the_fast_one_of_the_same_slo_only(self):
        rules = [r for r in CONFIG["inhibit_rules"] if r["equal"] == ["slo"]]

        def any_inhibits(source, target):
            return any(inhibited(r, source, target) for r in rules)

        fastest = {"alertname": "PaymentsAuthorizationAvailabilityBurnFastest", "slo": "payments-authorization"}
        self.assertTrue(any_inhibits(fastest, {"alertname": "PaymentsAuthorizationAvailabilityBurnFast", "slo": "payments-authorization"}))
        self.assertFalse(any_inhibits(fastest, {"alertname": "PaymentsStatusReadBurnFast", "slo": "payments-status-read"}))
        # a fast alert does not silence the fastest one
        self.assertFalse(any_inhibits({"alertname": "PaymentsAuthorizationAvailabilityBurnFast", "slo": "payments-authorization"}, fastest))


if __name__ == "__main__":
    unittest.main()
