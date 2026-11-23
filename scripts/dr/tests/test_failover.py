import contextlib
import importlib.util
import io
import json
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location("failover", Path(__file__).resolve().parents[1] / "failover.py")
fo = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(fo)

MUTATING = {"update_rule_group", "update_item", "delete_item", "failover_global_cluster", "create_policy_version", "delete_policy_version",
            "set_default_policy_version", "start_automation_execution"}
BASE = ["--name-prefix", "pay", "--env", "stage", "--source-region", "eu-central-1", "--target-region", "us-east-1", "--cell", "cell-1",
        "--deny-policy-arn", "arn:aws:iam::1:policy/deny"]
FAILOVER = BASE + ["--run-id", "inc-1", "--auto"]
FAILBACK = BASE + ["--run-id", "back-1", "--mode", "failback", "--confirmed-by", "approver-a"]
STAND = "arn:aws:dynamodb:us-east-1:1:table/t"
OTHER = "arn:aws:dynamodb:us-east-2:1:table/t"


class ClientError(Exception):
    def __init__(self, code):
        super().__init__(code)
        self.response = {"Error": {"Code": code}}


class Fake:
    def __init__(self):
        self.calls = []
        self.rules, self.writer, self.lock_held, self.lag = "", "eu-central-1", False, 100.0
        self.lock_item = {"deny_version": {"S": "v1"}}
        self.down = set()

    def client(self, service, region):
        return Client(self, service, region)

    def names(self):
        return [c[2] for c in self.calls]

    def handle(self, service, region, name, kw):
        if region in self.down:
            raise ClientError("EndpointConnectionError")
        if name == "describe_rule_group":
            return {"UpdateToken": "t", "RuleGroup": {"RulesSource": {"RulesString": self.rules}}}
        if name == "update_rule_group":
            self.rules = kw["RuleGroup"]["RulesSource"]["RulesString"]
        elif name == "update_item" and "run_id" in kw["UpdateExpression"]:
            if self.lock_held:
                raise ClientError("ConditionalCheckFailedException")
        elif name == "get_item":
            return {"Item": self.lock_item}
        elif name == "describe_global_clusters":
            return {"GlobalClusters": [{"GlobalClusterMembers": [
                {"DBClusterArn": f"arn:aws:rds:{r}:1:cluster:c-{r}", "IsWriter": r == self.writer} for r in ("eu-central-1", "us-east-1", "us-east-2")]}]}
        elif name == "failover_global_cluster":
            self.writer = kw["TargetDbClusterIdentifier"].split(":")[3]
        elif name == "get_metric_statistics":
            return {"Datapoints": [{"Timestamp": 1, "Maximum": self.lag}] if self.lag is not None else []}
        elif name == "get_policy":
            return {"Policy": {"DefaultVersionId": "v1"}}
        elif name == "list_policy_versions":
            return {"Versions": [{"VersionId": f"v{i}", "IsDefaultVersion": i == 5, "CreateDate": i} for i in range(1, 6)]}
        elif name == "get_policy_version":
            return {"PolicyVersion": {"Document": {"Version": "2012-10-17", "Statement": [{"Effect": "Deny", "Action": ["dynamodb:PutItem"], "Resource": [STAND, OTHER]}]}}}
        return {}


class Client:
    def __init__(self, fake, service, region):
        self.fake, self.service, self.region = fake, service, region

    def __getattr__(self, name):
        def call(**kw):
            self.fake.calls.append((self.service, self.region, name, kw))
            return self.fake.handle(self.service, self.region, name, kw)
        return call


def run(fake, args):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        code = fo.main(list(args), client=fake.client, sleep=lambda s: None)
    return code, out.getvalue()


class FailoverTest(unittest.TestCase):
    def test_promotes_the_standby_and_fences_first(self):
        fake = Fake()
        code, out = run(fake, FAILOVER)
        self.assertEqual(code, 0)
        self.assertEqual(fake.writer, "us-east-1")
        self.assertIn("route53-health-check", out)
        self.assertIn("sid:900001", fake.rules)
        self.assertLess(fake.names().index("update_rule_group"), fake.names().index("failover_global_cluster"))

    def test_uses_the_naming_defaults(self):
        fake = Fake()
        run(fake, FAILOVER)
        names = {c[3].get("GlobalClusterIdentifier") or c[3].get("RuleGroupName") or c[3].get("TableName") for c in fake.calls}
        self.assertTrue({"pay-stage-euc1-aurora-cell-1", "pay-stage-euc1-psp-fence", "pay-stage-use1-dr-lock"} <= names)

    def test_manual_failover_needs_an_approver(self):
        fake = Fake()
        code, _ = run(fake, [a for a in FAILOVER if a != "--auto"])
        self.assertEqual(code, fo.EXIT_REFUSED)
        self.assertEqual(fake.calls, [])

    def test_unreachable_working_region_does_not_block_promotion(self):
        fake = Fake()
        fake.down = {"eu-central-1"}
        code, out = run(fake, FAILOVER)
        self.assertEqual(code, 0)
        self.assertEqual(fake.writer, "us-east-1")
        self.assertIn("fence-unverified", out)

    def test_held_lock_skips_promotion(self):
        fake = Fake()
        fake.lock_held = True
        code, _ = run(fake, FAILOVER)
        self.assertEqual(code, fo.EXIT_LOCK_HELD)
        self.assertEqual(fake.writer, "eu-central-1")

    def test_already_writer_is_not_promoted_again(self):
        fake = Fake()
        fake.writer = "us-east-1"
        run(fake, FAILOVER)
        self.assertNotIn("failover_global_cluster", fake.names())

    def test_dynamodb_writes_allowed_only_in_the_promoted_region(self):
        fake = Fake()
        run(fake, FAILOVER)
        created = [c for c in fake.calls if c[2] == "create_policy_version"]
        self.assertEqual(json.loads(created[0][3]["PolicyDocument"])["Statement"][0]["Resource"], [OTHER])
        saved = [c for c in fake.calls if c[2] == "update_item" and "deny_version" in c[3]["UpdateExpression"]]
        self.assertEqual(saved[0][3]["ExpressionAttributeValues"][":v"], {"S": "v1"})

    def test_oldest_policy_version_is_deleted_at_the_iam_limit(self):
        fake = Fake()
        run(fake, FAILOVER)
        self.assertEqual([c[3]["VersionId"] for c in fake.calls if c[2] == "delete_policy_version"], ["v1"])

    def test_the_reconcile_window_is_logged_after_the_promotion(self):
        fake = Fake()
        code, out = run(fake, FAILOVER)
        self.assertEqual(code, 0)
        self.assertIn('"event": "reconcile-window"', out)
        self.assertIn('"minutes": 5', out)
        self.assertNotIn("start_automation_execution", fake.names())

    def test_dry_run_changes_nothing(self):
        fake = Fake()
        code, out = run(fake, FAILOVER + ["--dry-run"])
        self.assertEqual(code, 0)
        self.assertEqual([c for c in fake.calls if c[2] in MUTATING], [])
        self.assertIn("would-promote-aurora", out)


class FailbackTest(unittest.TestCase):
    def setUp(self):
        self.fake = Fake()
        self.fake.writer = "us-east-1"
        self.fake.rules = "pass tcp 127.0.0.1 any -> 127.0.0.1 any (sid:900000; rev:1;)\ndrop tcp any any -> any any (msg:\"dr fence\"; sid:900001; rev:1;)"

    def test_returns_to_the_working_region_and_undoes_the_fence(self):
        code, _ = run(self.fake, FAILBACK)
        self.assertEqual(code, 0)
        self.assertEqual(self.fake.writer, "eu-central-1")
        self.assertNotIn("sid:900001", self.fake.rules)
        self.assertIn("sid:900000", self.fake.rules)
        restored = [c for c in self.fake.calls if c[2] == "set_default_policy_version"]
        self.assertEqual(restored[0][3]["VersionId"], "v1")
        self.assertIn("delete_item", self.fake.names())
        switch = [c for c in self.fake.calls if c[2] == "failover_global_cluster"]
        self.assertFalse(switch[0][3]["AllowDataLoss"])

    def test_needs_an_approver(self):
        code, _ = run(self.fake, [a for a in FAILBACK if a not in ("--confirmed-by", "approver-a")])
        self.assertEqual(code, fo.EXIT_REFUSED)
        self.assertEqual(self.fake.calls, [])

    def test_is_never_automatic(self):
        with self.assertRaises(SystemExit), contextlib.redirect_stderr(io.StringIO()):
            fo.parse_args(FAILBACK + ["--auto"])

    def test_refuses_when_the_lag_is_high_or_unknown(self):
        for lag in (5000.0, None):
            fake = Fake()
            fake.writer = "us-east-1"
            fake.lag = lag
            code, _ = run(fake, FAILBACK)
            self.assertEqual(code, fo.EXIT_REFUSED)
            self.assertEqual(fake.writer, "us-east-1")
            self.assertEqual([c for c in fake.calls if c[2] in MUTATING], [])

    def test_refuses_when_the_working_region_is_already_the_writer(self):
        fake = Fake()
        code, _ = run(fake, FAILBACK)
        self.assertEqual(code, fo.EXIT_REFUSED)


if __name__ == "__main__":
    unittest.main()
