#!/usr/bin/env python3
import argparse
import json
import sys
import time
import uuid

TOKEN_NAMESPACE = uuid.UUID("3b9d5a52-8e1c-5f47-b0a3-6c2e9d4f7a11")
EXIT_ABORTED, EXIT_MISMATCH = 2, 3


class Aborted(Exception):
    pass


def error_code(exc):
    return getattr(exc, "response", {}).get("Error", {}).get("Code", "")


def client_token(run_id, step):
    # SSM requires a UUID, and uuid5 keeps one token per run and step across re-runs
    return str(uuid.uuid5(TOKEN_NAMESPACE, f"{run_id}/{step}"))


def log(event, **fields):
    print(json.dumps({"event": event, "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), **fields}, sort_keys=True), flush=True)


def aws_client(service, region):
    import boto3  # imported late so the unit tests need no boto3

    return boto3.client(service, region_name=region)


class Migration:
    def __init__(self, args, client=aws_client, sleep=time.sleep, now=time.monotonic):
        self.a, self.client, self.sleep, self.now = args, client, sleep, now
        self.ddb = client("dynamodb", args.region)
        self.ssm = client("ssm", args.region)
        self.cw = client("cloudwatch", args.region)
        self.key = {"merchant_id": {"S": args.merchant}}

    def route(self):
        item = self.ddb.get_item(TableName=self.a.routing_table, Key=self.key, ConsistentRead=True).get("Item")
        if not item:
            raise Aborted(f"merchant {self.a.merchant} has no route")
        return {"cell": item["cell"]["S"], "frozen": item.get("frozen", {}).get("BOOL", False), "freeze_id": item.get("freeze_id", {}).get("S", "")}

    def act(self, step, **fields):
        log(("would-" if self.a.dry_run else "do-") + step, merchant=self.a.merchant, run_id=self.a.run_id, **fields)
        return not self.a.dry_run

    def run_document(self, document, step):
        if not self.act(step, document=document):
            return
        params = {"Merchant": [self.a.merchant], "SourceCell": [self.a.source_cell], "TargetCell": [self.a.target_cell]}
        # the client token makes a re-run of the same step return the same execution
        ex = self.ssm.start_automation_execution(DocumentName=document, Parameters=params, ClientToken=client_token(self.a.run_id, step))["AutomationExecutionId"]
        end = self.now() + self.a.step_timeout_s
        while True:
            status = self.ssm.get_automation_execution(AutomationExecutionId=ex)["AutomationExecution"]["AutomationExecutionStatus"]
            if status == "Success":
                return
            if status in ("Failed", "Cancelled", "TimedOut") or self.now() >= end:
                raise Aborted(f"{step} ended as {status}")
            self.sleep(self.a.poll_s)

    def drain_lag(self):
        stat = self.cw.get_metric_statistics(Namespace="Payments", MetricName="drain_lag_seconds", Dimensions=[{"Name": "cell", "Value": self.a.source_cell}],
                                             StartTime=time.time() - 120, EndTime=time.time(), Period=60, Statistics=["Maximum"])
        points = sorted(stat["Datapoints"], key=lambda p: p["Timestamp"])
        return points[-1]["Maximum"] if points else float("inf")

    def freeze(self):
        if not self.act("freeze-writes", cell=self.a.source_cell):
            return
        try:
            self.ddb.update_item(TableName=self.a.routing_table, Key=self.key, UpdateExpression="SET frozen = :t, freeze_id = :id",
                                 ConditionExpression="#c = :src AND (attribute_not_exists(frozen) OR frozen = :f OR freeze_id = :id)",
                                 ExpressionAttributeNames={"#c": "cell"},
                                 ExpressionAttributeValues={":t": {"BOOL": True}, ":f": {"BOOL": False}, ":id": {"S": self.a.run_id}, ":src": {"S": self.a.source_cell}})
        except Exception as exc:
            if error_code(exc) == "ConditionalCheckFailedException":
                raise Aborted("merchant is not in the source cell or is frozen by another run") from exc
            raise

    def unfreeze(self):
        if self.a.dry_run:
            return
        try:
            self.ddb.update_item(TableName=self.a.routing_table, Key=self.key, UpdateExpression="SET frozen = :f REMOVE freeze_id",
                                 ConditionExpression="#c = :src AND freeze_id = :id", ExpressionAttributeNames={"#c": "cell"},
                                 ExpressionAttributeValues={":f": {"BOOL": False}, ":src": {"S": self.a.source_cell}, ":id": {"S": self.a.run_id}})
            log("unfrozen", merchant=self.a.merchant, cell=self.a.source_cell)
        except Exception as exc:
            if error_code(exc) != "ConditionalCheckFailedException":
                raise

    def wait_drained(self):
        end = self.now() + self.a.drain_wait_s
        while self.drain_lag() > self.a.max_drain_lag_s:
            if self.now() >= end:
                raise Aborted("drain lag did not reach the limit inside the freeze window")
            self.sleep(1)

    def switch(self):
        if not self.act("switch-route", source=self.a.source_cell, target=self.a.target_cell):
            return
        self.ddb.update_item(TableName=self.a.routing_table, Key=self.key, UpdateExpression="SET #c = :dst, frozen = :f REMOVE freeze_id",
                             ConditionExpression="#c = :src AND frozen = :t AND freeze_id = :id", ExpressionAttributeNames={"#c": "cell"},
                             ExpressionAttributeValues={":dst": {"S": self.a.target_cell}, ":src": {"S": self.a.source_cell}, ":f": {"BOOL": False},
                                                        ":t": {"BOOL": True}, ":id": {"S": self.a.run_id}})

    def run(self):
        if self.a.source_cell == self.a.target_cell:
            raise Aborted("source and target cell are the same")
        state = self.route()
        if state["cell"] == self.a.target_cell and not state["frozen"]:
            log("skip", reason="merchant already routed to the target cell", merchant=self.a.merchant)
            return
        if state["cell"] != self.a.source_cell:
            raise Aborted(f"merchant is in {state['cell']}, not in {self.a.source_cell}")
        self.run_document("cell-copy-merchant", "copy")
        self.freeze()
        started = self.now()
        try:
            # gateways cache the route, so writes may still reach the source cell until the cache expires
            if self.act("wait-route-cache", seconds=self.a.route_cache_ttl_s):
                self.sleep(self.a.route_cache_ttl_s)
            self.run_document("cell-copy-merchant", "copy-delta")
            if not self.a.dry_run:
                self.wait_drained()
            self.run_document("cell-verify-merchant", "verify")
            if self.now() - started > self.a.max_freeze_s:
                raise Aborted("freeze window exceeded before the route was switched")
            self.switch()
        except Exception:
            self.unfreeze()
            raise
        log("migrated", merchant=self.a.merchant, source=self.a.source_cell, target=self.a.target_cell, dry_run=self.a.dry_run)


def parse_args(argv):
    ap = argparse.ArgumentParser(description="Move one merchant between cells: copy, short write freeze, route switch")
    ap.add_argument("--merchant", required=True)
    ap.add_argument("--source-cell", required=True)
    ap.add_argument("--target-cell", required=True)
    ap.add_argument("--run-id", required=True)
    ap.add_argument("--region", default="eu-central-1")
    ap.add_argument("--routing-table", default="pay-prod-euc1-merchant-routing")
    ap.add_argument("--route-cache-ttl-s", type=int, default=60)
    ap.add_argument("--max-freeze-s", type=int, default=120)
    ap.add_argument("--max-drain-lag-s", type=float, default=0.5)
    ap.add_argument("--drain-wait-s", type=int, default=20)
    ap.add_argument("--step-timeout-s", type=int, default=1800)
    ap.add_argument("--poll-s", type=int, default=10)
    ap.add_argument("--dry-run", action="store_true")
    ns = ap.parse_args(argv)
    if ns.max_freeze_s <= ns.route_cache_ttl_s:
        ap.error("--max-freeze-s must exceed --route-cache-ttl-s, or the freeze ends before the gateways see it")
    return ns


def main(argv=None, **kw):
    ns = parse_args(argv if argv is not None else sys.argv[1:])
    try:
        Migration(ns, **kw).run()
    except Aborted as exc:
        log("aborted", reason=str(exc))
        return EXIT_ABORTED
    return 0


if __name__ == "__main__":
    sys.exit(main())
