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

ENV = {"NAME_PREFIX": "pay", "SOURCE_REGION": "eu-central-1", "TARGET_REGION": "us-east-1", "ENVIRONMENT": "stage",
       "LOCK_TABLE": "pay-stage-use1-dr-lock", "FENCE_RULE_GROUP": "pay-stage-euc1-psp-fence",
       "DENY_POLICY_ARN": "arn:aws:iam::1:policy/deny", "CELLS": json.dumps(["cell-0", "cell-1"])}


def event(state):
    msg = {"NewStateValue": state, "StateChangeTime": "2026-11-23T10:00:00.000+0000"}
    return {"Records": [{"Sns": {"Message": json.dumps(msg)}}]}


class HandlerTest(unittest.TestCase):
    def test_ok_state_is_ignored(self):
        with mock.patch.object(lh.failover, "main") as main:
            self.assertEqual(lh.handler(event("OK"), None), {"status": "ignored"})
            main.assert_not_called()

    def test_alarm_runs_every_cell_in_failover_mode_with_a_stable_run_id(self):
        with mock.patch.dict(os.environ, ENV), mock.patch.object(lh.failover, "main", return_value=0) as main:
            out = lh.handler(event("ALARM"), None)
        self.assertEqual(out["results"], {"cell-0": 0, "cell-1": 0})
        argv = main.call_args_list[0].args[0]
        self.assertEqual(argv[argv.index("--run-id") + 1], "hc-2026-11-23T10:00:00.000+0000-cell-0")
        self.assertIn("--auto", argv)
        self.assertEqual(argv[argv.index("--env") + 1], "stage")
        self.assertNotIn("failback", argv)

    def test_failed_cell_raises_so_the_alarm_retries(self):
        with mock.patch.dict(os.environ, ENV), mock.patch.object(lh.failover, "main", side_effect=[0, 1]):
            with self.assertRaises(RuntimeError):
                lh.handler(event("ALARM"), None)

    def test_held_lock_is_not_a_failure(self):
        with mock.patch.dict(os.environ, ENV), mock.patch.object(lh.failover, "main", return_value=lh.failover.EXIT_LOCK_HELD):
            self.assertEqual(lh.handler(event("ALARM"), None)["status"], "done")


    def test_pilot_light_creates_every_writer_before_any_wait(self):
        env = dict(ENV, SWITCH_WRITER_CLASSES=json.dumps({"cell-0": "db.r7g.12xlarge", "cell-1": "db.r7g.4xlarge"}),
                   COMPUTE_BUILD_URL="https://api.github.com/repos/o/r/actions/workflows/dr-compute-build.yml/dispatches",
                   COMPUTE_BUILD_SECRET="arn:aws:secretsmanager:us-east-1:1:secret:t")
        P = lh.failover.EXIT_PENDING
        with mock.patch.dict(os.environ, env), mock.patch.object(lh.failover, "main", side_effect=[P, P, 0, 0]) as main:
            out = lh.handler(event("ALARM"), Context(600_000))
        calls = [c.args[0] for c in main.call_args_list]
        self.assertEqual([a[a.index("--max-wait") + 1] for a in calls[:2]], ["0", "0"])
        self.assertTrue(all(int(a[a.index("--max-wait") + 1]) > 500 for a in calls[2:]))
        self.assertEqual(calls[1][calls[1].index("--writer-class") + 1], "db.r7g.4xlarge")
        self.assertEqual(calls[0][calls[0].index("--build-id") + 1], "hc-2026-11-23T10:00:00.000+0000")
        self.assertEqual(len(calls), 4)
        self.assertFalse(any("--await-build" in a for a in calls))
        self.assertEqual(out["results"], {"cell-0": 0, "cell-1": 0})

    def test_pending_raises_so_lambda_retries_the_same_switch(self):
        P = lh.failover.EXIT_PENDING
        with mock.patch.dict(os.environ, ENV), mock.patch.object(lh.failover, "main", side_effect=[P, 0, P, 0]), \
                self.assertRaisesRegex(RuntimeError, "pending for .'cell-0'."):
            lh.handler(event("ALARM"), Context(600_000))

    def test_warm_standby_passes_no_pilot_light_flags(self):
        with mock.patch.dict(os.environ, ENV), mock.patch.object(lh.failover, "main", return_value=0) as main:
            lh.handler(event("ALARM"), None)
        argv = main.call_args_list[0].args[0]
        self.assertFalse({"--writer-class", "--compute-build-url", "--await-build"} & set(argv))
        self.assertEqual(main.call_count, 2)


class Context:
    def __init__(self, ms):
        self.ms = ms

    def get_remaining_time_in_millis(self):
        return self.ms


if __name__ == "__main__":
    unittest.main()
