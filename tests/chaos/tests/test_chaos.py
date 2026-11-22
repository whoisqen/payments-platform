import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "lib"))
sys.path.insert(0, str(ROOT / "region-switch"))

import guard  # noqa: E402
import runner  # noqa: E402
import validate_fis  # noqa: E402

try:
    import yaml
except ImportError:
    yaml = None

PRIMARY = runner.load(ROOT / "region-switch" / "scenario.json")
PLAN_B = runner.load(ROOT / "region-switch" / "plan-b.json")


class FisTemplates(unittest.TestCase):
    def test_all_templates_are_valid(self):
        files = sorted((ROOT / "fis").glob("*.json"))
        self.assertGreaterEqual(len(files), 6)
        for f in files:
            with self.subTest(f=f.name):
                self.assertEqual(validate_fis.validate(f), [])

    def test_validator_rejects_bad_templates(self):
        bad = json.loads((ROOT / "fis" / "az-loss.json").read_text())
        bad["stopConditions"] = [{"source": "none"}]
        bad["actions"]["disrupt-az"]["parameters"].pop("duration")
        bad["tags"]["environment"] = "prod"
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "bad.json"
            path.write_text(json.dumps(bad))
            errors = validate_fis.validate(path)
        self.assertEqual(len(errors), 3)


@unittest.skipIf(yaml is None, "PyYAML is not installed")
class ChaosMeshManifests(unittest.TestCase):
    def test_manifests_carry_hypothesis_stop_and_failure_mode(self):
        files = sorted((ROOT / "chaos-mesh").glob("*.yaml"))
        self.assertEqual(len(files), 3)
        for f in files:
            with self.subTest(f=f.name):
                doc = yaml.safe_load(f.read_text())
                self.assertEqual(doc["apiVersion"], "chaos-mesh.org/v1alpha1")
                self.assertIn("chaos.payments/hypothesis", doc["metadata"]["annotations"])
                self.assertIn("chaos.payments/stop-condition", doc["metadata"]["annotations"])
                self.assertIn("failure-mode", doc["metadata"]["labels"])
                self.assertIn("duration", doc["spec"])


class Guard(unittest.TestCase):
    def test_runs_only_on_stage_without_freeze_or_incident(self):
        self.assertTrue(guard.may_run({"environment": "stage"})[0])
        for ctx in ({"environment": "prod"}, {"environment": "stage", "freeze": True}, {"environment": "stage", "open_incidents": 1}):
            self.assertFalse(guard.may_run(ctx)[0], ctx)


class RegionSwitch(unittest.TestCase):
    def test_scenarios_are_valid(self):
        self.assertEqual(runner.validate(PRIMARY), [])
        self.assertEqual(runner.validate(PLAN_B), [])

    def test_critical_path_matches_the_d7_budget(self):
        self.assertEqual(runner.rto_minutes(PRIMARY), 54)
        self.assertEqual(PRIMARY["rto_target_min"], 60)
        self.assertEqual(runner.rto_minutes(PLAN_B), 64)
        self.assertEqual(PLAN_B["rto_target_min"], 75)
        self.assertEqual({PRIMARY["target_region"], PLAN_B["target_region"]}, {"us-east-1", "us-east-2"})

    def test_overrun_beyond_the_target_is_caught(self):
        self.assertGreater(runner.rto_minutes(PRIMARY, {"create-eks-base": 7}), PRIMARY["rto_target_min"])

    def test_cycle_and_missing_fence_are_rejected(self):
        broken = json.loads(json.dumps(PRIMARY))
        next(s for s in broken["steps"] if s["id"] == "promote-aurora")["after"] = ["detect-confirm"]
        self.assertTrue(any("fence" in e for e in runner.validate(broken)))
        broken = json.loads(json.dumps(PRIMARY))
        broken["steps"][0]["after"] = ["traffic-switch"]
        self.assertTrue(any("cycle" in e for e in runner.validate(broken)))

    def test_abort_before_and_after_the_point_of_no_return(self):
        unfenced = {"frankfurt_writes_per_s": 3, "aurora_global_lag_seconds": 1, "authorization_rate_delta_pp": 0}
        self.assertEqual(runner.evaluate_abort(PRIMARY, unfenced, "promote-aurora"), [("A1", "abort")])
        lagging = dict(unfenced, frankfurt_writes_per_s=0, aurora_global_lag_seconds=12)
        self.assertEqual(runner.evaluate_abort(PRIMARY, lagging, "promote-aurora"), [("A2", "abort")])
        dropped = {"frankfurt_writes_per_s": 0, "aurora_global_lag_seconds": 1, "authorization_rate_delta_pp": -3}
        self.assertEqual(runner.evaluate_abort(PRIMARY, dropped, "traffic-switch"), [("A3", "halt-escalate")])
        self.assertEqual(runner.evaluate_abort(PRIMARY, unfenced, "traffic-switch"), [])

    def test_steady_state_evaluation(self):
        good = {
            "authorization_rate_delta_pp": -0.5, "platform_overhead_p99_ms": 120, "server_error_ratio": 0.00001,
            "writers_count": 1, "cache_warm_ratio": 0.8, "drain_lag_p99_s": 2, "unreconciled_charges": 0,
        }
        self.assertTrue(all(runner.evaluate_steady_state(PRIMARY, good).values()))
        self.assertFalse(runner.evaluate_steady_state(PRIMARY, dict(good, writers_count=2))["S4"])

    def test_dry_run_refuses_during_freeze(self):
        path = str(ROOT / "region-switch" / "scenario.json")
        self.assertEqual(runner.main([path, "--dry-run"]), 0)
        self.assertEqual(runner.main([path, "--dry-run", "--context", '{"environment":"stage","freeze":true}']), 2)


if __name__ == "__main__":
    unittest.main()
