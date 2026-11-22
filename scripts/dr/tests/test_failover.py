import contextlib
import importlib.util
import io
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location("failover", Path(__file__).resolve().parents[1] / "failover.py")
fo = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(fo)

MUTATING = {"update_rule_group", "update_endpoint_group", "update_item", "start_automation_execution",
            "failover_global_cluster", "stop_automation_execution"}
SRC_EG, USE1_EG, USE2_EG = "arn:eg:src", "arn:eg:use1", "arn:eg:use2"
ARGS = ["--cell", "cell-1", "--run-id", "inc-42", "--confirmed-by", "oncall-a", "--source-endpoint-group", SRC_EG,
        "--target-endpoint-group", f"us-east-1={USE1_EG}", "--target-endpoint-group", f"us-east-2={USE2_EG}", "--poll-s", "30"]


class ClientError(Exception):
    def __init__(self, code):
        super().__init__(code)
        self.response = {"Error": {"Code": code}}


class Fake:
    def __init__(self):
        self.calls, self.t = [], 0.0
        self.rules, self.dial = "", {SRC_EG: 100, USE1_EG: 0, USE2_EG: 0}
        self.lock, self.writer, self.fence_sticks, self.lock_held = None, "eu-central-1", True, False
        self.ssm_status, self.warm = {}, 0.9

    def client(self, service, region):
        return Client(self, service, region)

    def names(self):
        return [c[2] for c in self.calls]

    def handle(self, service, region, name, kw):
        if name == "describe_rule_group":
            return {"UpdateToken": "t", "RuleGroup": {"RulesSource": {"RulesString": self.rules}}}
        if name == "update_rule_group":
            if self.fence_sticks:
                self.rules = kw["RuleGroup"]["RulesSource"]["RulesString"]
        elif name == "describe_endpoint_group":
            return {"EndpointGroup": {"TrafficDialPercentage": self.dial[kw["EndpointGroupArn"]]}}
        elif name == "update_endpoint_group":
            self.dial[kw["EndpointGroupArn"]] = kw["TrafficDialPercentage"]
        elif name == "update_item" and "UpdateExpression" in kw and "run_id" in kw["UpdateExpression"]:
            if self.lock_held:
                raise ClientError("ConditionalCheckFailedException")
            self.lock = self.lock or {"region": ""}
        elif name == "update_item":
            self.lock["region"] = kw["ExpressionAttributeValues"][":v"]["S"]
        elif name == "get_item":
            return {"Item": {"region": {"S": self.lock["region"]}}}
        elif name == "start_automation_execution":
            return {"AutomationExecutionId": f"{region}|{kw['DocumentName']}"}
        elif name == "get_automation_execution":
            key = kw["AutomationExecutionId"]
            return {"AutomationExecution": {"AutomationExecutionStatus": self.ssm_status.get(key, "Success")}}
        elif name == "describe_global_clusters":
            return {"GlobalClusters": [{"GlobalClusterMembers": [
                {"DBClusterArn": f"arn:aws:rds:{r}:1:cluster:x", "IsWriter": r == self.writer} for r in ("eu-central-1", "us-east-1", "us-east-2")]}]}
        elif name == "failover_global_cluster":
            self.writer = kw["TargetDbClusterIdentifier"].split(":")[3]
        elif name == "get_metric_statistics":
            return {"Datapoints": [{"Timestamp": self.t, "Minimum": self.warm}]}
        return {}


class Client:
    def __init__(self, fake, service, region):
        self.fake, self.service, self.region = fake, service, region

    def __getattr__(self, name):
        def call(**kw):
            self.fake.calls.append((self.service, self.region, name, kw))
            return self.fake.handle(self.service, self.region, name, kw)
        return call


def run(fake, extra=(), args=ARGS):
    ns = fo.parse_args(list(args) + list(extra))
    out = io.StringIO()
    sleep = lambda s: setattr(fake, "t", fake.t + s)  # noqa: E731
    with contextlib.redirect_stdout(out):
        code = fo.main(list(args) + list(extra), client=fake.client, sleep=sleep, now=lambda: fake.t)
    return code, out.getvalue(), ns


class FailoverTest(unittest.TestCase):
    def mutating(self, fake):
        return [c for c in fake.calls if c[2] in MUTATING]

    def test_refuses_without_on_call_confirmation(self):
        fake = Fake()
        args = [a for a in ARGS if a not in ("--confirmed-by", "oncall-a")]
        code, _, _ = run(fake, args=args)
        self.assertEqual(code, fo.EXIT_REFUSED)
        self.assertEqual(fake.calls, [])

    def test_fencing_is_first_and_before_every_other_change(self):
        fake = Fake()
        code, _, _ = run(fake)
        self.assertEqual(code, 0)
        names = [(c[0], c[2]) for c in self.mutating(fake)]
        self.assertEqual(names[0], ("network-firewall", "update_rule_group"))
        self.assertEqual(names[1], ("globalaccelerator", "update_endpoint_group"))
        self.assertLess(fake.names().index("update_rule_group"), fake.names().index("failover_global_cluster"))
        self.assertLess(fake.names().index("update_rule_group"), fake.names().index("update_item"))
        self.assertEqual(fake.dial, {SRC_EG: 0, USE1_EG: 100, USE2_EG: 0})

    def test_failed_fence_verification_stops_everything(self):
        fake = Fake()
        fake.fence_sticks = False
        code, _, _ = run(fake)
        self.assertEqual(code, fo.EXIT_REFUSED)
        self.assertNotIn("failover_global_cluster", fake.names())
        self.assertNotIn("update_item", fake.names())

    def test_promotion_refuses_without_fence(self):
        fake = Fake()
        ns = fo.parse_args(ARGS)
        f = fo.Failover(ns, client=fake.client)
        with self.assertRaises(fo.Refused):
            f.promote_aurora()
        self.assertNotIn("failover_global_cluster", fake.names())

    def test_held_lock_skips_without_promotion(self):
        fake = Fake()
        fake.lock_held = True
        code, _, _ = run(fake)
        self.assertEqual(code, fo.EXIT_LOCK_HELD)
        self.assertNotIn("failover_global_cluster", fake.names())

    def test_plan_b_after_ten_minutes_without_capacity(self):
        fake = Fake()
        fake.ssm_status["us-east-1|dr-create-compute"] = "InProgress"
        code, out, _ = run(fake)
        self.assertEqual(code, 0)
        self.assertGreaterEqual(fake.t, 600)
        self.assertEqual(fake.writer, "us-east-2")
        self.assertEqual(fake.lock["region"], "us-east-2")
        self.assertEqual(fake.dial[USE2_EG], 100)
        self.assertEqual(fake.dial[USE1_EG], 0)
        self.assertIn("stop_automation_execution", fake.names())
        self.assertEqual(fake.names().count("failover_global_cluster"), 1)
        self.assertIn("no-capacity", out)

    def test_no_capacity_anywhere_refuses_before_promotion(self):
        fake = Fake()
        fake.ssm_status["us-east-1|dr-create-compute"] = "Failed"
        fake.ssm_status["us-east-2|dr-create-compute"] = "Failed"
        code, _, _ = run(fake)
        self.assertEqual(code, fo.EXIT_REFUSED)
        self.assertNotIn("failover_global_cluster", fake.names())

    def test_rerun_after_success_changes_nothing_but_the_idempotent_documents(self):
        fake = Fake()
        run(fake)
        fake.calls.clear()
        code, _, _ = run(fake)
        self.assertEqual(code, 0)
        changed = {c[2] for c in self.mutating(fake)} - {"start_automation_execution", "update_item"}
        self.assertEqual(changed, set())
        self.assertEqual([c for c in fake.calls if c[2] == "update_item" and "run_id" not in c[3]["UpdateExpression"]], [])

    def test_resumed_run_keeps_its_region(self):
        fake = Fake()
        fake.ssm_status["us-east-1|dr-create-compute"] = "InProgress"
        run(fake)
        fake.ssm_status.clear()
        fake.calls.clear()
        run(fake)
        creates = [c for c in fake.calls if c[2] == "start_automation_execution" and c[3]["DocumentName"] == "dr-create-compute"]
        self.assertEqual({c[1] for c in creates}, {"us-east-2"})

    def test_dry_run_changes_nothing(self):
        fake = Fake()
        code, out, _ = run(fake, ["--dry-run"])
        self.assertEqual(code, 0)
        self.assertEqual(self.mutating(fake), [])
        self.assertIn("would-fence-firewall", out)
        self.assertEqual(fake.writer, "eu-central-1")

    def test_low_cache_warm_ratio_does_not_block_traffic(self):
        fake = Fake()
        fake.warm = 0.4
        code, out, _ = run(fake)
        self.assertEqual(code, 0)
        self.assertIn("warm-below-target", out)
        self.assertEqual(fake.dial[USE1_EG], 100)

    def test_reconciliation_window_is_five_minutes(self):
        fake = Fake()
        run(fake)
        rec = [c for c in fake.calls if c[2] == "start_automation_execution" and c[3]["DocumentName"] == "dr-psp-reconcile"]
        self.assertEqual(rec[0][3]["Parameters"]["WindowMinutes"], ["5"])

    def test_logs_are_json_lines(self):
        import json
        fake = Fake()
        _, out, _ = run(fake)
        for line in out.splitlines():
            self.assertIn("event", json.loads(line))


if __name__ == "__main__":
    unittest.main()
