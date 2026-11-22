import json
import re
import sys
import unittest
from pathlib import Path

import yaml

EXP = Path(__file__).resolve().parents[1]
OBS = EXP.parent
DOCS = {p.stem: [d for d in yaml.safe_load_all(p.read_text()) if d] for p in sorted(EXP.glob("*.yaml"))}
CATALOG = json.loads((OBS / "coverage" / "metrics-catalog.json").read_text())["metrics"]
SOURCE_FILE = {"postgres-exporter": "postgres", "redis-exporter": "redis", "kafka-exporter": "kafka", "clickhouse": "clickhouse", "blackbox-exporter": "blackbox"}
FORBIDDEN = ("payment_id", "customer_id", "token", "pan", "card_number", "cvv")


def monitors(name):
    return [d for d in DOCS[name] if d.get("kind") in ("ServiceMonitor", "PodMonitor")]


def keep_regexes(name):
    out = []
    for mon in monitors(name):
        for ep in mon["spec"].get("endpoints", []) + mon["spec"].get("podMetricsEndpoints", []):
            out += [re.compile(f"(?:{r['regex']})") for r in ep.get("metricRelabelings", []) if r["action"] == "keep"]
    return out


class ExporterTest(unittest.TestCase):
    def test_five_exporters_with_a_monitor_each_except_blackbox_probes(self):
        self.assertEqual(sorted(DOCS), ["blackbox", "clickhouse", "kafka", "postgres", "redis"])
        for name in ("postgres", "redis", "kafka", "clickhouse"):
            self.assertTrue(monitors(name), name)

    def test_every_catalogued_metric_of_a_source_is_kept_by_its_allowlist(self):
        for metric, source in CATALOG.items():
            if source in ("postgres-exporter", "redis-exporter", "kafka-exporter", "clickhouse"):
                with self.subTest(metric=metric):
                    self.assertTrue(any(r.fullmatch(metric) for r in keep_regexes(SOURCE_FILE[source])), f"{metric} is dropped by relabeling")

    def test_blackbox_metrics_are_exposed_unfiltered(self):
        probes = [m for m, s in CATALOG.items() if s == "blackbox-exporter"]
        self.assertTrue(probes)
        for name in ("probe_success", "probe_ssl_earliest_cert_expiry"):
            self.assertIn(name, probes)

    def test_label_allowlist_drops_card_and_identifier_labels(self):
        for name in ("postgres", "redis", "clickhouse"):
            drops = [r["regex"] for m in monitors(name) for ep in m["spec"]["endpoints"] for r in ep["metricRelabelings"] if r["action"] == "labeldrop"]
            self.assertTrue(drops, name)
            for word in ("payment_id", "customer_id", "token", "pan", "cvv"):
                self.assertTrue(any(re.fullmatch(d, word) for d in drops), f"{name} keeps {word}")

    def test_postgres_custom_queries_expose_hashes_not_statement_text(self):
        values = DOCS["postgres"][0]
        queries = yaml.safe_load(values["config"]["queries"])
        self.assertNotIn("query:", json.dumps(queries["pg_stat_statements"]["metrics"]))
        self.assertIn("LIMIT 20", queries["pg_stat_statements"]["query"])
        self.assertIn("LIMIT 20", queries["pg_table"]["query"])

    def test_no_credentials_in_values(self):
        for name, docs in DOCS.items():
            text = yaml.safe_dump(docs)
            self.assertNotRegex(text, r"://[^/\s]*:[^/\s@]+@", name)
        self.assertIn("secret", yaml.safe_dump(DOCS["postgres"][0]).lower())


class BlackboxProbePointsTest(unittest.TestCase):
    probes = [d for d in DOCS["blackbox"] if d.get("kind") == "Probe"]

    def test_three_independent_points_outside_the_working_region(self):
        points = {p["spec"]["targets"]["staticConfig"]["labels"]["probe_point"] for p in self.probes}
        self.assertEqual(points, {"use1", "use2", "ext"})
        urls = [p["spec"]["prober"]["url"] for p in self.probes]
        self.assertEqual(len(set(urls)), 3)
        for url in urls:
            self.assertNotIn("euc1", url)
            self.assertNotIn("eu-central-1", url)

    def test_each_point_probes_the_region_health_endpoint_and_every_public_target(self):
        for p in self.probes:
            targets = p["spec"]["targets"]["staticConfig"]["static"]
            kinds = {re.search(r"/probe/([a-z-]+)$", t).group(1) for t in targets}
            self.assertEqual(kinds, {"region-health", "api", "webhook-in", "control-center"})

    def test_relabeling_yields_the_labels_the_alerts_use(self):
        rules = self.probes[0]["spec"]["targets"]["staticConfig"]["relabelingConfigs"]
        self.assertEqual({r["targetLabel"] for r in rules}, {"target", "probe_target", "region"})
        url = "https://api.eu-central-1.payments.internal/probe/region-health"
        for r in rules:
            m = re.fullmatch(r["regex"], url) or re.match(r["regex"], url)
            self.assertIsNotNone(m, r["targetLabel"])
        region = re.match(rules[2]["regex"], url).group(1)
        self.assertEqual(region, "eu-central-1")


if __name__ == "__main__":
    unittest.main()
