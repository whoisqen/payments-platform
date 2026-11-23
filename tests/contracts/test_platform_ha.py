import sys
import unittest
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from contracts import model  # noqa: E402

PLATFORM = model.DEPLOY / "platform"


def values(name):
    return yaml.safe_load((PLATFORM / name / "values.yaml").read_text(encoding="utf-8"))


class PrometheusHA(unittest.TestCase):
    def setUp(self):
        self.v = values("kube-prometheus")["prometheus"]
        self.spec = self.v["prometheusSpec"]

    def test_two_replicas_so_one_can_be_down(self):
        self.assertGreaterEqual(self.spec["replicas"], 2)

    def test_replicas_do_not_share_a_node_and_spread_over_zones(self):
        self.assertEqual(self.spec["podAntiAffinity"], "hard")
        self.assertEqual(self.spec["podAntiAffinityTopologyKey"], "kubernetes.io/hostname")
        self.assertIn("topology.kubernetes.io/zone", [t["topologyKey"] for t in self.spec["topologySpreadConstraints"]])

    def test_a_voluntary_disruption_leaves_one_replica(self):
        self.assertTrue(self.v["podDisruptionBudget"]["enabled"])
        self.assertGreaterEqual(self.v["podDisruptionBudget"]["minAvailable"], 1)

    def test_no_replica_label_so_the_central_store_can_deduplicate(self):
        # a differing label keeps the two samples apart; VictoriaMetrics deduplicates identical series
        self.assertEqual(self.spec["replicaExternalLabelName"], "")


class CollectorHA(unittest.TestCase):
    def test_the_collector_runs_on_every_node(self):
        self.assertEqual(values("otel-collector")["mode"], "daemonset")


if __name__ == "__main__":
    unittest.main()
