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
            "set_default_policy_version", "start_automation_execution", "create_db_instance", "POST"}
BASE = ["--name-prefix", "pay", "--env", "stage", "--source-region", "eu-central-1", "--target-region", "us-east-1", "--cell", "cell-1",
        "--deny-policy-arn", "arn:aws:iam::1:policy/deny"]
FAILOVER = BASE + ["--run-id", "inc-1", "--auto"]
FAILBACK = BASE + ["--run-id", "back-1", "--mode", "failback", "--confirmed-by", "approver-a"]
STAND = "arn:aws:dynamodb:us-east-1:1:table/t"
OTHER = "arn:aws:dynamodb:us-east-2:1:table/t"
DISPATCH = "https://api.github.com/repos/o/r/actions/workflows/dr-compute-build.yml/dispatches"
PILOT = FAILOVER + ["--writer-class", "db.r7g.12xlarge", "--compute-build-url", DISPATCH, "--compute-build-secret",
                    "arn:aws:secretsmanager:us-east-1:1:secret:dr-build-token", "--build-id", "hc-1"]


class ClientError(Exception):
    def __init__(self, code):
        super().__init__(code)
        self.response = {"Error": {"Code": code}}


class Fake:
    def __init__(self):
        self.calls = []
        self.rules, self.writer, self.lock_held, self.lag = "", "eu-central-1", False, 100.0
        self.lock_item = {"deny_version": {"S": "v1"}}
        self.items, self.default_version, self.post_fails = {}, "v1", 0
        self.down = set()
        self.policy_doc = {"Version": "2012-10-17", "Statement": [{"Effect": "Deny", "Action": ["dynamodb:PutItem"], "Resource": [STAND, OTHER]}]}
        self.instances, self.ready_after, self.instance_polls = {}, 2, 0
        self.runs, self.build_polls, self.build_done_after, self.conclusion = [], 0, 3, "success"
        self.dispatched_recently, self.hide_members = False, False
        self.t = 0.0

    def sleep(self, seconds):
        self.t += seconds

    def now(self):
        return self.t

    def http(self, method, url, token, body=None):
        self.calls.append(("github", "", method, {"url": url, "token": token, "body": body}))
        if method == "POST" and self.post_fails:
            self.post_fails -= 1
            raise OSError("HTTP 502")
        if method == "POST":
            self.runs.append({"display_title": f"dr-compute-build {body['inputs']['environment']} {body['inputs']['incident']}", "status": "queued",
                              "html_url": "https://github.com/o/r/actions/runs/1"})
            return {}
        self.build_polls += 1
        if self.build_polls >= self.build_done_after:
            for r in self.runs:
                r.update(status="completed", conclusion=self.conclusion)
        return {"workflow_runs": [dict(r) for r in self.runs]}

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
        elif name == "update_item" and "dispatched_at" in kw["UpdateExpression"]:
            if self.dispatched_recently:
                raise ClientError("ConditionalCheckFailedException")
        elif name == "get_secret_value":
            return {"SecretString": json.dumps({"token": "tkn"})}
        elif name == "describe_db_clusters":
            return {"DBClusters": [{"Engine": "aurora-postgresql", "TagList": [{"Key": "cell", "Value": "cell-1"}],
                                    "DBClusterMembers": [] if self.hide_members else [{"DBInstanceIdentifier": i} for i in self.instances]}]}
        elif name == "create_db_instance":
            if kw["DBInstanceIdentifier"] in self.instances:
                raise ClientError("DBInstanceAlreadyExists")
            self.instances[kw["DBInstanceIdentifier"]] = "creating"
        elif name == "describe_db_instances":
            self.instance_polls += 1
            if self.instance_polls >= self.ready_after:
                self.instances = {i: "available" for i in self.instances}
            return {"DBInstances": [{"DBInstanceIdentifier": i, "DBInstanceStatus": st} for i, st in self.instances.items()]}
        elif name == "update_item" and "deny_version" in kw["UpdateExpression"]:
            self.items[kw["Key"]["pk"]["S"]] = {"deny_version": kw["ExpressionAttributeValues"][":v"]}
        elif name == "get_item":
            pk = kw["Key"]["pk"]["S"]
            return {"Item": self.items.get(pk, self.lock_item if pk.startswith("dr-switch#") else {})}
        elif name == "describe_global_clusters":
            return {"GlobalClusters": [{"GlobalClusterMembers": [
                {"DBClusterArn": f"arn:aws:rds:{r}:1:cluster:c-{r}", "IsWriter": r == self.writer} for r in ("eu-central-1", "us-east-1", "us-east-2")]}]}
        elif name == "failover_global_cluster":
            self.writer = kw["TargetDbClusterIdentifier"].split(":")[3]
        elif name == "get_metric_statistics":
            return {"Datapoints": [{"Timestamp": 1, "Maximum": self.lag}] if self.lag is not None else []}
        elif name == "get_policy":
            return {"Policy": {"DefaultVersionId": self.default_version}}
        elif name == "set_default_policy_version":
            self.default_version = kw["VersionId"]
        elif name == "list_policy_versions":
            return {"Versions": [{"VersionId": f"v{i}", "IsDefaultVersion": i == 5, "CreateDate": i} for i in range(1, 6)]}
        elif name == "get_policy_version":
            return {"PolicyVersion": {"Document": json.loads(json.dumps(self.policy_doc))}}
        elif name == "create_policy_version":
            self.policy_doc, self.default_version = json.loads(kw["PolicyDocument"]), "v6"
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
        code = fo.main(list(args), client=fake.client, sleep=fake.sleep, now=fake.now, http=fake.http)
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


class PilotLightTest(unittest.TestCase):
    def index(self, fake, name):
        return fake.names().index(name)

    def test_build_starts_first_then_writer_then_promotion(self):
        fake = Fake()
        code, out = run(fake, PILOT)
        self.assertEqual(code, 0)
        self.assertEqual(fake.writer, "us-east-1")
        self.assertLess(self.index(fake, "POST"), self.index(fake, "create_db_instance"))
        self.assertLess(self.index(fake, "create_db_instance"), self.index(fake, "describe_db_instances"))
        self.assertLess(self.index(fake, "describe_db_instances"), self.index(fake, "failover_global_cluster"))
        created = next(c[3] for c in fake.calls if c[2] == "create_db_instance")
        self.assertEqual((created["DBInstanceIdentifier"], created["DBClusterIdentifier"], created["DBInstanceClass"], created["Engine"]),
                         ("c-us-east-1-writer", "c-us-east-1", "db.r7g.12xlarge", "aurora-postgresql"))
        self.assertEqual(created["Tags"], [{"Key": "cell", "Value": "cell-1"}])
        post = next(c[3] for c in fake.calls if c[2] == "POST")
        self.assertEqual(post["token"], "tkn")
        self.assertEqual(post["body"]["inputs"], {"environment": "stage", "region": "us-east-1", "incident": "hc-1", "trigger": "switch",
                                                  "confirm": "switch stage"})
        self.assertIn("writer-available", out)

    def test_secret_is_read_in_the_region_of_its_arn(self):
        fake = Fake()
        run(fake, PILOT)
        self.assertEqual({c[1] for c in fake.calls if c[2] == "get_secret_value"}, {"us-east-1"})

    def test_every_step_logs_its_duration(self):
        fake = Fake()
        _, out = run(fake, PILOT)
        done = [json.loads(line) for line in out.splitlines() if '"step-done"' in line]
        self.assertEqual([d["name"] for d in done][:7], ["confirm", "fence", "acquire_lock", "start_compute_build", "add_writer", "wait_writer",
                                                          "promote_aurora"])
        self.assertEqual(next(d for d in done if d["name"] == "wait_writer")["seconds"], fo.POLL_SECONDS)

    def test_writer_not_ready_by_the_deadline_ends_pending_and_a_rerun_resumes(self):
        fake = Fake()
        fake.ready_after = 100
        code, out = run(fake, PILOT + ["--max-wait", "0"])
        self.assertEqual(code, fo.EXIT_PENDING)
        self.assertIn('"event": "pending"', out)
        self.assertNotIn("failover_global_cluster", fake.names())
        fake.ready_after = 0
        code, _ = run(fake, PILOT)
        self.assertEqual(code, 0)
        self.assertEqual(fake.writer, "us-east-1")
        self.assertEqual(fake.names().count("create_db_instance"), 1)
        self.assertEqual(fake.names().count("POST"), 1)

    def test_cluster_with_an_instance_gets_no_writer(self):
        fake = Fake()
        fake.instances = {"c-us-east-1-0": "available"}
        code, _ = run(fake, PILOT)
        self.assertEqual(code, 0)
        self.assertNotIn("create_db_instance", fake.names())

    def test_writer_created_by_a_crashed_run_is_reused(self):
        fake = Fake()
        fake.instances, fake.hide_members = {"c-us-east-1-writer": "creating"}, True
        code, _ = run(fake, PILOT)
        self.assertEqual(code, 0)
        self.assertEqual(fake.names().count("create_db_instance"), 1)
        self.assertEqual(fake.writer, "us-east-1")

    def test_one_build_per_incident_for_all_cells(self):
        fake = Fake()
        run(fake, PILOT)
        run(fake, [a if a != "cell-1" else "cell-2" for a in PILOT])
        self.assertEqual(fake.names().count("POST"), 1)

    def test_concurrent_dispatch_is_skipped_by_the_lock_item(self):
        fake = Fake()
        fake.dispatched_recently = True
        code, out = run(fake, PILOT)
        self.assertEqual(code, 0)
        self.assertNotIn("POST", fake.names())
        self.assertIn("dispatched by another run", out)
        lock = next(c[3] for c in fake.calls if c[2] == "update_item" and "dispatched_at" in c[3]["UpdateExpression"])
        self.assertEqual(lock["Key"], {"pk": {"S": "dr-compute-build#hc-1"}})

    def test_await_build_waits_for_success(self):
        fake = Fake()
        code, out = run(fake, PILOT + ["--await-build"])
        self.assertEqual(code, 0)
        self.assertIn("compute-build-done", out)
        self.assertLess(self.index(fake, "failover_global_cluster"), max(i for i, n in enumerate(fake.names()) if n == "GET"))

    def test_failed_build_fails_the_run(self):
        fake = Fake()
        fake.conclusion = "failure"
        code, out = run(fake, PILOT + ["--await-build"])
        self.assertEqual(code, 1)
        self.assertEqual(fake.writer, "us-east-1")
        self.assertIn("ended with failure", out)

    def test_slow_build_ends_pending_after_the_promotion(self):
        fake = Fake()
        fake.build_done_after = 1000
        code, _ = run(fake, PILOT + ["--await-build", "--max-wait", "120"])
        self.assertEqual(code, fo.EXIT_PENDING)
        self.assertEqual(fake.writer, "us-east-1")

    def test_rerun_after_the_promotion_keeps_the_deny_version_and_window(self):
        fake = Fake()
        run(fake, PILOT)
        code, out = run(fake, PILOT)
        self.assertEqual(code, 0)
        self.assertEqual(fake.names().count("create_policy_version"), 1)
        self.assertIn("skip-reconcile-window", out)
        self.assertIn("skip-allow-dynamodb-writes", out)

    def test_dry_run_changes_nothing_and_reads_no_token(self):
        fake = Fake()
        code, out = run(fake, PILOT + ["--await-build", "--dry-run"])
        self.assertEqual(code, 0)
        self.assertEqual([c for c in fake.calls if c[2] in MUTATING], [])
        self.assertNotIn("get_secret_value", fake.names())
        for event in ("would-dispatch-compute-build", "would-add-writer", "would-wait-writer", "would-promote-aurora", "would-wait-compute-build"):
            self.assertIn(event, out)

    def test_failed_dispatch_clears_its_marker_so_a_retry_dispatches(self):
        fake = Fake()
        fake.post_fails = 1
        code, _ = run(fake, PILOT)
        self.assertEqual(code, 1)
        self.assertTrue(any(c[2] == "update_item" and c[3]["UpdateExpression"] == "REMOVE dispatched_at" for c in fake.calls))
        code, _ = run(fake, PILOT)
        self.assertEqual(code, 0)
        self.assertEqual(len(fake.runs), 1)

    def test_build_url_needs_a_secret(self):
        with self.assertRaises(SystemExit), contextlib.redirect_stderr(io.StringIO()):
            fo.parse_args(FAILOVER + ["--compute-build-url", DISPATCH])

    def test_without_pilot_light_flags_nothing_new_is_called(self):
        fake = Fake()
        run(fake, FAILOVER)
        self.assertFalse({"create_db_instance", "describe_db_clusters", "get_secret_value", "POST", "GET"} & set(fake.names()))


class FailbackTest(unittest.TestCase):
    def setUp(self):
        self.fake = Fake()
        self.fake.writer = "us-east-1"
        self.fake.default_version = "v6"
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

    def test_every_cell_fails_back_after_a_multi_cell_failover(self):
        fake = Fake()
        fake.lock_item = {}
        for cell in ("cell-0", "cell-1"):
            fake.writer = "eu-central-1"
            self.assertEqual(run(fake, [a if a != "cell-1" else cell for a in FAILOVER])[0], 0)
        self.assertEqual(fake.names().count("create_policy_version"), 1)
        fake.rules = "drop tcp any any -> any any (msg:\"dr fence\"; sid:900001; rev:1;)"
        for cell in ("cell-0", "cell-1"):
            fake.writer = "us-east-1"
            self.assertEqual(run(fake, [a if a != "cell-1" else cell for a in FAILBACK])[0], 0, cell)
        self.assertEqual(fake.default_version, "v1")
        self.assertEqual(fake.names().count("set_default_policy_version"), 1)

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
