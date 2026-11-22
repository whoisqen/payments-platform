import copy
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

import capacity  # noqa: E402
import miniyaml  # noqa: E402

CFG = capacity.load(ROOT / "pod-capacity.yaml")
FORECAST = capacity.load(ROOT / "forecast.yaml")


class MiniYaml(unittest.TestCase):
    def test_scalars_nesting_and_comments(self):
        doc = miniyaml.loads("# c\na: 1\nb:\n  c: 0.7  # why\n  d: null\n  e: text\n  f: true\n")
        self.assertEqual(doc, {"a": 1, "b": {"c": 0.7, "d": None, "e": "text", "f": True}})

    def test_matches_pyyaml_when_available(self):
        try:
            import yaml
        except ImportError:
            self.skipTest("PyYAML is not installed")
        for name in ("pod-capacity.yaml", "forecast.yaml"):
            text = (ROOT / name).read_text()
            self.assertEqual(miniyaml.loads(text), yaml.safe_load(text), name)


class Replicas(unittest.TestCase):
    def test_router_target_capacity_matches_the_document(self):
        r = capacity.replicas(CFG, FORECAST, "target")["router"]
        self.assertEqual((r["min"], r["max"]), (20, 90))
        self.assertEqual(r["sale_pods"], 239)

    def test_router_baseline_capacity_is_within_one_pod_of_the_document(self):
        r = capacity.replicas(CFG, FORECAST, "baseline")["router"]
        self.assertLessEqual(abs(r["min"] - 79), 1)
        self.assertLessEqual(abs(r["max"] - 357), 1)
        self.assertLessEqual(abs(r["sale_pods"] - 952), 2)

    def test_other_components_stay_within_one_pod_of_the_document(self):
        got = capacity.replicas(CFG, FORECAST)
        doc = {"drainer": (3, 6, 14), "scheduler-consumer": (3, 12, 31), "locker": (5, 24, 17)}
        for name, (lo, hi, sale) in doc.items():
            with self.subTest(name=name):
                self.assertLessEqual(abs(got[name]["min"] - lo), 1)
                self.assertLessEqual(abs(got[name]["max"] - hi), 1)
                self.assertLessEqual(abs(got[name]["sale_pods"] - sale), 1)

    def test_floor_of_three_and_fixed_producer(self):
        got = capacity.replicas(CFG, {"tps": {"daily_peak": 1, "sale_peak": 2}})
        self.assertEqual(got["router"]["min"], 3)
        self.assertEqual(got["scheduler-producer"], {"scope": "cell", "min": 2, "max": 2, "sale_pods": 8})

    def test_confirmed_capacity_replaces_the_baseline(self):
        cfg = copy.deepcopy(CFG)
        cfg["components"]["router"]["confirmed_per_pod"] = 60
        self.assertEqual(capacity.replicas(cfg, FORECAST)["router"]["max"], 90)

    def test_replicas_never_decrease_with_load(self):
        low = capacity.replicas(CFG, {"tps": {"daily_peak": 100, "sale_peak": 300}})
        high = capacity.replicas(CFG, FORECAST)
        for name in low:
            self.assertLessEqual(low[name]["max"], high[name]["max"])


class Regression(unittest.TestCase):
    def _with_router(self, value):
        cfg = copy.deepcopy(CFG)
        cfg["components"]["router"]["confirmed_per_pod"] = value
        return cfg

    def test_drop_above_15_percent_is_a_regression(self):
        found = capacity.regressions(self._with_router(60), self._with_router(50))
        self.assertEqual([f["component"] for f in found], ["router"])
        self.assertEqual(found[0]["drop"], 0.167)

    def test_drop_of_exactly_15_percent_or_less_passes(self):
        self.assertEqual(capacity.regressions(self._with_router(60), self._with_router(51)), [])
        self.assertEqual(capacity.regressions(self._with_router(60), self._with_router(70)), [])

    def test_removed_component_is_a_regression(self):
        new = copy.deepcopy(CFG)
        del new["components"]["locker"]
        self.assertEqual([f["component"] for f in capacity.regressions(CFG, new)], ["locker"])


if __name__ == "__main__":
    unittest.main()
