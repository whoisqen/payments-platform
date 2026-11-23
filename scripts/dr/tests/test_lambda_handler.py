import importlib.util
import json
import os
import sys
import unittest
from pathlib import Path
from unittest import mock

DR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(DR))
SPEC = importlib.util.spec_from_file_location("lambda_handler", DR / "lambda_handler.py")
lh = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(lh)

ENV = {"NAME_PREFIX": "pay", "SOURCE_REGION": "eu-central-1", "TARGET_REGION": "us-east-1", "FALLBACK_REGION": "us-east-2",
       "LOCK_TABLE": "pay-stage-use1-dr-lock", "GLOBAL_CLUSTER_PATTERN": "pay-stage-{cell}-aurora-payments", "FENCE_RULE_GROUP": "pay-stage-euc1-psp-fence",
       "DENY_POLICY_ARN": "arn:aws:iam::1:policy/deny", "CELLS": json.dumps(["cell-0", "cell-1"])}


def event(state):
    msg = {"NewStateValue": state, "StateChangeTime": "2026-11-23T10:00:00.000+0000"}
    return {"Records": [{"Sns": {"Message": json.dumps(msg)}}]}


class HandlerTest(unittest.TestCase):
    def test_ok_state_is_ignored(self):
        with mock.patch.object(lh.failover, "main") as main:
            self.assertEqual(lh.handler(event("OK"), None), {"status": "ignored"})
            main.assert_not_called()

    def test_alarm_runs_every_cell_in_warm_mode_with_a_stable_run_id(self):
        with mock.patch.dict(os.environ, ENV), mock.patch.object(lh.failover, "main", return_value=0) as main:
            out = lh.handler(event("ALARM"), None)
        self.assertEqual(out["results"], {"cell-0": 0, "cell-1": 0})
        argv = main.call_args_list[0].args[0]
        self.assertEqual(argv[argv.index("--run-id") + 1], "hc-2026-11-23T10:00:00.000+0000-cell-0")
        self.assertIn("--auto", argv)
        self.assertEqual(argv[argv.index("--mode") + 1], "warm")
        self.assertEqual(argv[argv.index("--global-cluster") + 1], "pay-stage-cell-0-aurora-payments")

    def test_failed_cell_raises_so_the_alarm_retries(self):
        with mock.patch.dict(os.environ, ENV), mock.patch.object(lh.failover, "main", side_effect=[0, 1]):
            with self.assertRaises(RuntimeError):
                lh.handler(event("ALARM"), None)

    def test_held_lock_is_not_a_failure(self):
        with mock.patch.dict(os.environ, ENV), mock.patch.object(lh.failover, "main", return_value=lh.failover.EXIT_LOCK_HELD):
            self.assertEqual(lh.handler(event("ALARM"), None)["status"], "done")


if __name__ == "__main__":
    unittest.main()
