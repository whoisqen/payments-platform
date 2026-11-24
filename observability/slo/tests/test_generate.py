import copy
import sys
import unittest
from pathlib import Path

import yaml

SLO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SLO))
import generate  # noqa: E402

DOCS = {p.name: yaml.safe_load(p.read_text()) for p in generate.sources()}
BUDGET_MINUTES = {"payments-authorization": 4.3, "payments-platform-overhead": 43.2, "payments-status": 21.6, "payments-webhooks": 43.2}


def all_groups(doc):
    """The rules of the in-cluster Prometheus and the ones of the central rule evaluator."""
    return generate.build(doc)["spec"]["groups"] + generate.build(doc, central=True)["spec"]["groups"]


def alerts(doc):
    rules = all_groups(doc)
    return {r["alert"]: r for g in rules for r in g["rules"] if "alert" in r}


class SlothShapeTest(unittest.TestCase):
    def test_four_slos_of_section_1(self):
        self.assertEqual(len(DOCS), 4)
        self.assertEqual(sorted(d["service"] for d in DOCS.values()), sorted(BUDGET_MINUTES))

    def test_files_follow_the_sloth_v1_shape(self):
        for name, doc in DOCS.items():
            self.assertEqual(doc["version"], "prometheus/v1", name)
            for slo in doc["slos"]:
                self.assertIn("error_query", slo["sli"]["events"])
                self.assertIn("total_query", slo["sli"]["events"])
                self.assertIn("{{.window}}", slo["sli"]["events"]["error_query"])
                self.assertIn("{{.window}}", slo["sli"]["events"]["total_query"])
                for key in ("summary", "runbook_url", "dashboard_url"):
                    self.assertIn(key, slo["alerting"]["annotations"])

    def test_error_budget_matches_the_table(self):
        for doc in DOCS.values():
            minutes = (1 - doc["slos"][0]["objective"] / 100) * 43200
            self.assertAlmostEqual(minutes, BUDGET_MINUTES[doc["service"]], delta=0.05)


class GeneratedRulesTest(unittest.TestCase):
    def test_only_the_99_99_slo_gets_the_fastest_window(self):
        for doc in DOCS.values():
            names = alerts(doc)
            fastest = [n for n in names if n.endswith("BurnFastest")]
            self.assertEqual(len(fastest), 1 if doc["service"] == "payments-authorization" else 0, doc["service"])
            self.assertEqual(len(names), 4 if fastest else 3)

    def test_rules_that_look_back_beyond_the_local_retention_are_central_only(self):
        for doc in DOCS.values():
            local = {r.get("record") or r["alert"] for g in generate.build(doc)["spec"]["groups"] for r in g["rules"]}
            far = {r.get("record") or r["alert"] for g in generate.build(doc, central=True)["spec"]["groups"] for r in g["rules"]}
            self.assertFalse(local & far)
            self.assertTrue({"slo:sli_error:ratio_rate3d", "slo:sli_error:ratio_rate30d", "slo:period_burn_rate:ratio"} <= far)
            self.assertTrue(any(n.endswith("BurnTicket") for n in far))
            self.assertFalse(any(n.endswith(("BurnFast", "BurnSlow")) for n in far))

    def test_burn_rates_and_window_pairs(self):
        auth = alerts(DOCS["authorization-availability.yaml"])
        self.assertIn("ratio_rate5m{", auth["PaymentsAuthorizationAvailabilityBurnFastest"]["expr"])
        self.assertIn("ratio_rate1m{", auth["PaymentsAuthorizationAvailabilityBurnFastest"]["expr"])
        self.assertIn("(50 * 0.0001)", auth["PaymentsAuthorizationAvailabilityBurnFastest"]["expr"])
        fast = auth["PaymentsAuthorizationAvailabilityBurnFast"]["expr"]
        self.assertIn("ratio_rate1h{", fast)
        self.assertIn("ratio_rate5m{", fast)
        self.assertIn("(14.4 * 0.0001)", fast)
        slow = auth["PaymentsAuthorizationAvailabilityBurnSlow"]["expr"]
        self.assertTrue("ratio_rate6h{" in slow and "ratio_rate30m{" in slow and "(6 * 0.0001)" in slow)
        ticket = auth["PaymentsAuthorizationAvailabilityBurnTicket"]["expr"]
        self.assertTrue("ratio_rate3d{" in ticket and "ratio_rate6h{" in ticket and "(1 * 0.0001)" in ticket)

    def test_budget_follows_the_objective(self):
        for doc in DOCS.values():
            budget = generate.fmt(1 - doc["slos"][0]["objective"] / 100)
            for rule in alerts(doc).values():
                self.assertIn(f"* {budget})", rule["expr"])

    def test_page_and_ticket_severities(self):
        for doc in DOCS.values():
            for name, rule in alerts(doc).items():
                self.assertEqual(rule["labels"]["severity"], "warning" if name.endswith("BurnTicket") else "critical", name)

    def test_every_alert_has_the_mandatory_labels(self):
        for doc in DOCS.values():
            for rule in alerts(doc).values():
                for key in ("severity", "team", "service", "owner", "layer", "failure_mode", "slo"):
                    self.assertIn(key, rule["labels"])
                self.assertIn("summary", rule["annotations"])

    def test_recording_rules_cover_every_window_used(self):
        for doc in DOCS.values():
            spec = all_groups(doc)
            records = {r["record"] for g in spec for r in g["rules"] if "record" in r}
            for rule in alerts(doc).values():
                for window in ("1m", "5m", "30m", "1h", "6h", "3d"):
                    if f"ratio_rate{window}{{" in rule["expr"]:
                        self.assertIn(f"slo:sli_error:ratio_rate{window}", records)
            self.assertIn("slo:period_error_budget_remaining:ratio", records)

    def test_no_high_cardinality_label_in_generated_rules(self):
        for doc in DOCS.values():
            text = yaml.safe_dump(generate.build(doc))
            for word in ("payment_id", "customer_id", "card_number"):
                self.assertNotIn(word, text)

    def test_unknown_objective_changes_the_threshold(self):
        doc = copy.deepcopy(DOCS["merchant-webhook-delivery.yaml"])
        doc["slos"][0]["objective"] = 99.5
        self.assertIn("(14.4 * 0.005)", alerts(doc)["PaymentsWebhookDeliveryBurnFast"]["expr"])

    def test_committed_files_are_current(self):
        self.assertEqual(generate.main(["--check"]), 0)


if __name__ == "__main__":
    unittest.main()
