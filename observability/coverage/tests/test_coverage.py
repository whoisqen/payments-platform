import json
import sys
import tempfile
import unittest
from pathlib import Path

import yaml

COV = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(COV))
import alert_coverage as cov  # noqa: E402

URL = "{{ $externalLabels.runbook_base_url }}/docs/runbooks/x/{}.md"


def rule(name, expr="up == 0", **over):
    r = {"alert": name, "expr": expr, "labels": {"severity": "critical", "team": "t", "service": "s", "owner": "o"},
         "annotations": {"summary": "s", "runbook_url": URL.format(name), "dashboard_url": "d"}}
    r.update(over)
    return r


class ExtractMetricsTest(unittest.TestCase):
    def test_plain_selector_and_threshold(self):
        self.assertEqual(cov.extract_metrics('pg_up{role="writer"} == 0'), {"pg_up"})

    def test_functions_aggregations_and_ranges_are_not_metrics(self):
        expr = 'sum by (cell) (rate(redis_evicted_keys_total{cell="a"}[5m])) > 0'
        self.assertEqual(cov.extract_metrics(expr), {"redis_evicted_keys_total"})

    def test_binary_ops_offset_and_matching(self):
        expr = "max by (s) (a_total offset 1d) / on (s) group_left max by (s) (b_bytes) > 1.2 and c_seconds"
        self.assertEqual(cov.extract_metrics(expr), {"a_total", "b_bytes", "c_seconds"})

    def test_numbers_units_and_strings_are_ignored(self):
        expr = 'time() - m_timestamp_seconds > 2 * 86400 and x{l="up or down"} < 1e9'
        self.assertEqual(cov.extract_metrics(expr), {"m_timestamp_seconds", "x"})

    def test_recording_rule_names_with_colons(self):
        self.assertEqual(cov.extract_metrics('slo:sli_error:ratio_rate5m{sloth_id="a"} > 0.1'), {"slo:sli_error:ratio_rate5m"})

    def test_histogram_quantile(self):
        expr = "histogram_quantile(0.99, sum by (le) (rate(d_seconds_bucket[5m]))) > 3"
        self.assertEqual(cov.extract_metrics(expr), {"d_seconds_bucket"})


class CheckModeTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = Path(self.tmp.name)
        (self.repo / "docs" / "runbooks" / "x").mkdir(parents=True)
        self.addCleanup(self.tmp.cleanup)

    def runbook(self, name, text="# t\n\n## Diagnostics\n1. look\n"):
        (self.repo / "docs" / "runbooks" / "x" / f"{name}.md").write_text(text)

    def check(self, mode, alerts, metrics=("up",)):
        return cov.check_mode(mode, alerts, set(), set(metrics), self.repo)

    def test_covered_mode(self):
        self.runbook("A")
        self.assertIsNone(self.check({"alert": "A"}, {"A": rule("A")}))

    def test_mode_without_alert_is_a_gap(self):
        self.assertEqual(self.check({"alert": None}, {}), "no alert defined")

    def test_missing_alert_in_rules(self):
        self.assertIn("not found", self.check({"alert": "A"}, {}))

    def test_missing_label_or_annotation(self):
        bad = rule("A")
        del bad["labels"]["owner"]
        self.assertIn("owner", self.check({"alert": "A"}, {"A": bad}))
        bad = rule("A")
        del bad["annotations"]["runbook_url"]
        self.assertIn("runbook_url", self.check({"alert": "A"}, {"A": bad}))

    def test_missing_runbook_file(self):
        self.assertEqual(self.check({"alert": "A"}, {"A": rule("A")}), "runbook file does not exist")

    def test_runbook_without_diagnostics(self):
        self.runbook("A", "# t\n\n## Actions\n")
        self.assertEqual(self.check({"alert": "A"}, {"A": rule("A")}), "runbook has no diagnostics")

    def test_alert_on_a_metric_that_is_not_exported_does_not_count(self):
        self.runbook("A")
        reason = self.check({"alert": "A"}, {"A": rule("A", expr="ghost_metric > 1")})
        self.assertEqual(reason, "metric not exported: ghost_metric")

    def test_recorded_series_count_as_exported(self):
        self.runbook("A")
        alerts = {"A": rule("A", expr="slo:x:ratio > 1")}
        self.assertIsNone(cov.check_mode({"alert": "A"}, alerts, {"slo:x:ratio"}, set(), self.repo))

    def test_ratio_and_target(self):
        self.runbook("A")
        modes = [{"id": "l-a", "layer": "l", "alert": "A"}, {"id": "l-b", "layer": "l", "alert": None}, {"id": "m-a", "layer": "m", "alert": "A"}]
        layers = cov.compute(modes, {"A": rule("A")}, set(), {"up"}, {"default": 0.8, "l": 0.9}, self.repo)
        self.assertEqual(layers["l"]["ratio"], 0.5)
        self.assertFalse(layers["l"]["meets_target"])
        self.assertEqual(layers["l"]["uncovered"][0]["id"], "l-b")
        self.assertTrue(layers["m"]["meets_target"])


class RealRepositoryTest(unittest.TestCase):
    def test_every_layer_meets_its_target(self):
        out = Path(tempfile.mkdtemp()) / "report.json"
        self.assertEqual(cov.main(["--out", str(out), "--fail-below-target"]), 0)
        report = json.loads(out.read_text())
        self.assertEqual(sorted(report["layers"]), ["application", "backup-dr", "compute", "data", "meta", "network", "security-pci"])
        self.assertEqual(report["alerts_without_failure_mode"], [])

    def test_targets_follow_section_25(self):
        targets = yaml.safe_load((COV / "targets.yaml").read_text())["targets"]
        for layer in ("data", "application", "security-pci", "backup-dr"):
            self.assertEqual(targets[layer], 0.9)
        for layer in ("network", "compute"):
            self.assertEqual(targets[layer], 0.8)

    def test_catalog_entries_have_the_documented_fields(self):
        for mode in cov.load_catalog(COV / "catalog"):
            for key in ("id", "layer", "component", "failure", "impact", "severity", "alert", "signal"):
                self.assertIn(key, mode, mode["id"])

    def test_report_is_not_committed(self):
        self.assertIn("report.json", (COV / ".gitignore").read_text())


if __name__ == "__main__":
    unittest.main()
