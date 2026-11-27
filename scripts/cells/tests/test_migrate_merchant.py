import contextlib
import importlib.util
import io
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location("migrate_merchant", Path(__file__).resolve().parents[1] / "migrate-merchant.py")
mm = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mm)

ARGS = ["--name-prefix", "pay", "--region", "eu-central-1", "--merchant", "m-1", "--source-cell", "cell-1", "--target-cell", "cell-2", "--run-id", "mig-7"]


class ClientError(Exception):
    def __init__(self, code):
        super().__init__(code)
        self.response = {"Error": {"Code": code}}


class Fake:
    def __init__(self, cell="cell-1", frozen=False):
        self.calls, self.t = [], 0.0
        self.item = {"cell": {"S": cell}, "frozen": {"BOOL": frozen}}
        self.lag, self.ssm = 0.0, {}

    def client(self, service, region):
        return Client(self, service)

    def names(self):
        return [c[0] for c in self.calls]


class Client:
    def __init__(self, fake, service):
        self.fake, self.service = fake, service

    def __getattr__(self, name):
        def call(**kw):
            f = self.fake
            f.calls.append((name, kw))
            if name == "get_item":
                return {"Item": f.item}
            if name == "update_item":
                expr = kw["UpdateExpression"]
                v = kw["ExpressionAttributeValues"]
                if expr.startswith("SET frozen = :t"):
                    if f.item["cell"]["S"] != v[":src"]["S"] or (f.item["frozen"]["BOOL"] and f.item.get("freeze_id", {}).get("S") != v[":id"]["S"]):
                        raise ClientError("ConditionalCheckFailedException")
                    f.item.update({"frozen": {"BOOL": True}, "freeze_id": {"S": v[":id"]["S"]}})
                elif expr.startswith("SET #c"):
                    f.item = {"cell": v[":dst"], "frozen": {"BOOL": False}}
                else:
                    f.item.update({"frozen": {"BOOL": False}})
                    f.item.pop("freeze_id", None)
            elif name == "start_automation_execution":
                return {"AutomationExecutionId": kw["DocumentName"]}
            elif name == "get_automation_execution":
                return {"AutomationExecution": {"AutomationExecutionStatus": f.ssm.get(kw["AutomationExecutionId"], "Success")}}
            elif name == "get_metric_statistics":
                return {"Datapoints": [{"Timestamp": f.t, "Maximum": f.lag}]}
            return {}
        return call


def run(fake, extra=()):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        code = mm.main(ARGS + list(extra), client=fake.client, sleep=lambda s: setattr(fake, "t", fake.t + s), now=lambda: fake.t)
    return code, out.getvalue()


class MigrateMerchantTest(unittest.TestCase):
    def test_happy_path_switches_route_and_unfreezes(self):
        fake = Fake()
        code, _ = run(fake)
        self.assertEqual(code, 0)
        self.assertEqual(fake.item["cell"]["S"], "cell-2")
        self.assertFalse(fake.item["frozen"]["BOOL"])

    def test_order_copy_freeze_delta_verify_switch(self):
        fake = Fake()
        run(fake)
        docs = [c[1]["DocumentName"] for c in fake.calls if c[0] == "start_automation_execution"]
        self.assertEqual(docs, ["cell-copy-merchant", "cell-copy-merchant", "cell-verify-merchant"])
        names = fake.names()
        self.assertLess(names.index("start_automation_execution"), names.index("update_item"))

    def test_rerun_after_success_is_a_noop(self):
        fake = Fake(cell="cell-2")
        code, out = run(fake)
        self.assertEqual(code, 0)
        self.assertNotIn("update_item", fake.names())
        self.assertIn("already routed", out)

    def test_verify_failure_unfreezes_and_keeps_the_route(self):
        fake = Fake()
        fake.ssm["cell-verify-merchant"] = "Failed"
        code, _ = run(fake)
        self.assertEqual(code, mm.EXIT_ABORTED)
        self.assertEqual(fake.item["cell"]["S"], "cell-1")
        self.assertFalse(fake.item["frozen"]["BOOL"])

    def test_frozen_by_another_run_aborts_without_touching_it(self):
        fake = Fake(frozen=True)
        fake.item["freeze_id"] = {"S": "other"}
        code, _ = run(fake)
        self.assertEqual(code, mm.EXIT_ABORTED)
        self.assertTrue(fake.item["frozen"]["BOOL"])

    def test_drain_lag_that_never_settles_aborts(self):
        fake = Fake()
        fake.lag = 9.0
        code, _ = run(fake)
        self.assertEqual(code, mm.EXIT_ABORTED)
        self.assertEqual(fake.item["cell"]["S"], "cell-1")

    def test_merchant_in_other_cell_aborts(self):
        code, _ = run(Fake(cell="cell-3"))
        self.assertEqual(code, mm.EXIT_ABORTED)

    def test_delta_copy_waits_for_the_route_cache(self):
        fake = Fake()
        stamps = {}
        orig = Client.__getattr__

        def spy(self, name):
            fn = orig(self, name)

            def call(**kw):
                if name == "update_item" and kw["UpdateExpression"].startswith("SET frozen = :t"):
                    stamps["freeze"] = self.fake.t
                if name == "start_automation_execution" and "freeze" in stamps and "delta" not in stamps:
                    stamps["delta"] = self.fake.t
                return fn(**kw)
            return call

        Client.__getattr__ = spy
        self.addCleanup(setattr, Client, "__getattr__", orig)
        code, _ = run(fake)
        self.assertEqual(code, 0)
        self.assertGreaterEqual(stamps["delta"] - stamps["freeze"], 60)

    def test_freeze_shorter_than_the_route_cache_is_rejected(self):
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            mm.parse_args(ARGS + ["--max-freeze-s", "30"])

    def test_default_routing_table_is_the_terraform_global_table(self):
        tf = Path(__file__).resolve().parents[3] / "infra/modules/dynamodb-global/variables.tf"
        self.assertIn('default     = "merchant-cell-map"', tf.read_text(encoding="utf-8"))
        for region in ("eu-central-1", "us-east-1"):
            args = [a if a != "eu-central-1" else region for a in ARGS]
            self.assertEqual(mm.parse_args(args).routing_table, "pay-prod-euc1-merchant-cell-map")
        self.assertEqual(mm.parse_args(ARGS + ["--routing-table", "t"]).routing_table, "t")

    def test_client_token_is_a_stable_uuid(self):
        import uuid
        t = mm.client_token("mig-7", "copy")
        self.assertEqual(str(uuid.UUID(t)), t)
        self.assertEqual(t, mm.client_token("mig-7", "copy"))
        self.assertNotEqual(t, mm.client_token("mig-7", "verify"))

    def test_dry_run_changes_nothing(self):
        fake = Fake()
        code, out = run(fake, ["--dry-run"])
        self.assertEqual(code, 0)
        self.assertNotIn("update_item", fake.names())
        self.assertNotIn("start_automation_execution", fake.names())
        self.assertIn("would-switch-route", out)


if __name__ == "__main__":
    unittest.main()
