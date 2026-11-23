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


class CentralStackHA(unittest.TestCase):
    def test_metrics_store_has_three_nodes_of_each_kind_and_stores_every_sample_twice(self):
        v = values("victoria-metrics")
        for part in ("vmselect", "vminsert", "vmstorage"):
            self.assertGreaterEqual(v[part]["replicaCount"], 3, part)
            self.assertTrue(v[part]["podDisruptionBudget"]["enabled"], part)
        self.assertEqual(v["vminsert"]["extraArgs"]["replicationFactor"], 2)

    def test_the_deduplication_interval_comes_from_the_config_in_both_places_that_need_it(self):
        addon = (model.DEPLOY / "argocd" / "templates" / "addons" / "central" / "victoria-metrics.yaml").read_text(encoding="utf-8")
        for part in ("vmselect", "vmstorage"):
            self.assertIn(part + r".extraArgs.dedup\.minScrapeInterval", addon)
        self.assertIn(".Values.central.dedupInterval", addon)

    def test_alertmanager_is_a_cluster_of_three(self):
        v = values("alertmanager")
        self.assertEqual(v["replicaCount"], 3)
        self.assertGreaterEqual(v["podDisruptionBudget"]["minAvailable"], 2)


class CollectorHA(unittest.TestCase):
    def test_the_collector_runs_on_every_node(self):
        self.assertEqual(values("otel-collector")["mode"], "daemonset")


if __name__ == "__main__":
    unittest.main()
