import sys
import unittest
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import render_otel  # noqa: E402

SOURCE = yaml.safe_load(render_otel.SRC.read_text(encoding="utf-8"))
VALUES = yaml.safe_load(render_otel.render())


class RenderOtelTest(unittest.TestCase):
    def test_committed_file_is_current(self):
        self.assertEqual(render_otel.OUT.read_text(encoding="utf-8"), render_otel.render())

    def test_processing_is_the_tested_one(self):
        cfg = VALUES["config"]
        self.assertEqual(cfg["processors"], SOURCE["processors"])
        self.assertEqual(cfg["connectors"], SOURCE["connectors"])
        for name in ("logs/detect", "logs/ship", "traces", "metrics"):
            self.assertEqual(cfg["service"]["pipelines"][name], SOURCE["service"]["pipelines"][name])

    def test_chart_defaults_that_would_bypass_the_masking_are_removed(self):
        cfg = VALUES["config"]
        self.assertIsNone(cfg["service"]["pipelines"]["logs"])
        self.assertIsNone(cfg["exporters"]["debug"])
        for receiver in ("jaeger", "zipkin", "prometheus"):
            self.assertIsNone(cfg["receivers"][receiver])

    def test_the_receiver_has_no_tls_and_stays_on_the_node(self):
        for proto in VALUES["config"]["receivers"]["otlp"]["protocols"].values():
            self.assertNotIn("tls", proto)
        self.assertEqual(VALUES["service"]["internalTrafficPolicy"], "Local")
        self.assertEqual(VALUES["mode"], "daemonset")

    def test_everything_that_leaves_the_cluster_keeps_mutual_tls(self):
        for name in ("otlphttp/central-logs", "otlp/central-traces", "prometheusremotewrite/central"):
            tls = VALUES["config"]["exporters"][name]["tls"]
            self.assertEqual(set(tls), {"ca_file", "cert_file", "key_file"}, name)

    def test_the_contrib_distribution_is_used_because_tail_sampling_needs_it(self):
        self.assertTrue(VALUES["image"]["repository"].endswith("opentelemetry-collector-contrib"))
        self.assertEqual(VALUES["command"]["name"], "otelcol-contrib")


if __name__ == "__main__":
    unittest.main()
