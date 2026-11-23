#!/usr/bin/env python3
import argparse
import json
import sys
import time
import uuid

TOKEN_NAMESPACE = uuid.UUID("6f2c1b7e-4d3a-5c1e-9a64-0d5b8e7f1a20")


def short(region):
    # eu-central-1 -> euc1, the region short code of the naming scheme
    a, b, c = region.split("-")
    return f"{a}{b[0]}{c}"


FENCE_SID = "sid:900001"
FENCE_RULE = f'drop tcp any any -> any any (msg:"dr fence"; {FENCE_SID}; rev:1;)'
WARM_TARGET = 0.75
EXIT_REFUSED, EXIT_LOCK_HELD = 2, 3


class Refused(Exception):
    pass


class LockHeld(Exception):
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


class Failover:
    def __init__(self, args, client=aws_client, sleep=time.sleep, now=time.monotonic):
        self.a = args
        self.client = client
        self.sleep = sleep
        self.now = now
        self.fenced = False
        self.region = None
        self.executions = {}

    def act(self, step, **fields):
        log(("would-" if self.a.dry_run else "do-") + step, cell=self.a.cell, run_id=self.a.run_id, **fields)
        return not self.a.dry_run

    def confirm(self):
        if not self.a.confirmed_by:
            raise Refused("no on-call confirmation: the switch is semi-automatic (ADR-015)")
        log("confirmed", confirmed_by=self.a.confirmed_by, run_id=self.a.run_id)

    def fence(self):
        src = self.a.source_region
        nf = self.client("network-firewall", src)
        ga = self.client("globalaccelerator", "us-west-2")
        group = nf.describe_rule_group(RuleGroupName=self.a.fence_rule_group, Type="STATEFUL")
        rules = group["RuleGroup"]["RulesSource"].get("RulesString", "")
        if FENCE_SID not in rules:
            if self.act("fence-firewall", rule_group=self.a.fence_rule_group):
                nf.update_rule_group(UpdateToken=group["UpdateToken"], RuleGroupName=self.a.fence_rule_group, Type="STATEFUL",
                                     RuleGroup={"RulesSource": {"RulesString": (rules + "\n" + FENCE_RULE).strip()}})
        eg = ga.describe_endpoint_group(EndpointGroupArn=self.a.source_endpoint_group)["EndpointGroup"]
        if eg["TrafficDialPercentage"] != 0:
            if self.act("fence-traffic", endpoint_group=self.a.source_endpoint_group):
                ga.update_endpoint_group(EndpointGroupArn=self.a.source_endpoint_group, TrafficDialPercentage=0)
        self.run_document(src, "dr-scale-router-zero", {"Cell": [self.a.cell]}, "fence-router")
        if self.a.dry_run:
            return
        again = nf.describe_rule_group(RuleGroupName=self.a.fence_rule_group, Type="STATEFUL")
        eg = ga.describe_endpoint_group(EndpointGroupArn=self.a.source_endpoint_group)["EndpointGroup"]
        if FENCE_SID not in again["RuleGroup"]["RulesSource"].get("RulesString", "") or eg["TrafficDialPercentage"] != 0:
            raise Refused("fencing of the source region could not be verified")
        self.fenced = True
        log("fenced", region=src, cell=self.a.cell)

    def run_document(self, region, document, params, step, timeout_s=None):
        ssm = self.client("ssm", region)
        # the client token makes a re-run of the same step return the same execution
        token = client_token(self.a.run_id, step)
        if not self.act(step, document=document, region=region):
            return None
        try:
            ex = ssm.start_automation_execution(DocumentName=document, Parameters=params, ClientToken=token)["AutomationExecutionId"]
        except Exception as exc:
            if error_code(exc) != "IdempotentParameterMismatch":
                raise
            raise Refused(f"{step}: execution with this token already exists with other parameters") from exc
        self.executions[step] = (ssm, ex)
        return self.wait_execution(ssm, ex, step, timeout_s or self.a.step_timeout_s)

    def wait_execution(self, ssm, ex, step, timeout_s):
        end = self.now() + timeout_s
        while True:
            status = ssm.get_automation_execution(AutomationExecutionId=ex)["AutomationExecution"]["AutomationExecutionStatus"]
            if status == "Success":
                return "Success"
            if status in ("Failed", "Cancelled", "TimedOut"):
                return status
            if self.now() >= end:
                return "TimedOut"
            self.sleep(self.a.poll_s)

    def acquire_lock(self):
        ddb = self.client("dynamodb", self.a.lock_region)
        key = {"pk": {"S": f"dr-switch#{self.a.cell}"}}
        if not self.act("acquire-lock", table=self.a.lock_table):
            return
        try:
            # if_not_exists keeps the region a resumed run already chose
            ddb.update_item(TableName=self.a.lock_table, Key=key, UpdateExpression="SET run_id = :r, #reg = if_not_exists(#reg, :empty)",
                            ConditionExpression="attribute_not_exists(pk) OR run_id = :r", ExpressionAttributeNames={"#reg": "region"},
                            ExpressionAttributeValues={":r": {"S": self.a.run_id}, ":empty": {"S": ""}})
        except Exception as exc:
            if error_code(exc) == "ConditionalCheckFailedException":
                raise LockHeld(f"switch lock of {self.a.cell} is held by another run") from exc
            raise
        # a resumed run keeps the region it chose first
        stored = ddb.get_item(TableName=self.a.lock_table, Key=key, ConsistentRead=True)["Item"]
        self.region = stored["region"]["S"] or None

    def ensure_compute(self):
        candidates = [self.region] if self.region else [self.a.target_region, self.a.fallback_region]
        for i, region in enumerate(candidates):
            # plan B starts after the capacity wait; the last candidate gets the full step timeout
            wait = self.a.capacity_wait_s if i < len(candidates) - 1 else None
            step = f"compute-{short(region)}"
            status = self.run_document(region, "dr-create-compute", {"Cell": [self.a.cell]}, step, timeout_s=wait)
            if self.a.dry_run or status == "Success":
                if self.region != region:
                    self.persist_region(region)
                self.region = region
                return region
            log("no-capacity", region=region, status=status)
            if step in self.executions:
                ssm, ex = self.executions[step]
                ssm.stop_automation_execution(AutomationExecutionId=ex, Type="Cancel")
        raise Refused("compute could not be created in any recovery region")

    def persist_region(self, region):
        if self.a.dry_run:
            return
        ddb = self.client("dynamodb", self.a.lock_region)
        ddb.update_item(TableName=self.a.lock_table, Key={"pk": {"S": f"dr-switch#{self.a.cell}"}},
                        UpdateExpression="SET #r = :v", ConditionExpression="run_id = :id",
                        ExpressionAttributeNames={"#r": "region"},
                        ExpressionAttributeValues={":v": {"S": region}, ":id": {"S": self.a.run_id}})

    def promote_aurora(self):
        if not self.fenced and not self.a.dry_run:
            raise Refused("promotion needs a verified fence first")
        region = self.region or self.a.target_region
        rds = self.client("rds", region)
        gc = rds.describe_global_clusters(GlobalClusterIdentifier=self.a.global_cluster)["GlobalClusters"][0]
        member = next((m for m in gc["GlobalClusterMembers"] if f":{region}:" in m["DBClusterArn"]), None)
        if member is None:
            raise Refused(f"no member of {self.a.global_cluster} in {region}")
        if member["IsWriter"]:
            log("skip-promote", reason="already writer", region=region)
            return
        # promotion is the point of no return and happens in exactly one region
        if self.act("promote-aurora", global_cluster=self.a.global_cluster, region=region):
            rds.failover_global_cluster(GlobalClusterIdentifier=self.a.global_cluster, TargetDbClusterIdentifier=member["DBClusterArn"],
                                        AllowDataLoss=True)

    def warm_memorydb(self):
        region = self.region or self.a.target_region
        status = self.run_document(region, "dr-rebuild-memorydb", {"Cell": [self.a.cell]}, "memorydb")
        if self.a.dry_run:
            return
        if status != "Success":
            raise Refused(f"MemoryDB rebuild ended as {status}")
        cw = self.client("cloudwatch", region)
        end = self.now() + self.a.warm_wait_s
        ratio = 0.0
        while True:
            ratio = self.warm_ratio(cw)
            if ratio >= WARM_TARGET or self.now() >= end:
                break
            self.sleep(self.a.poll_s)
        if ratio < WARM_TARGET:
            log("warm-below-target", ratio=ratio, target=WARM_TARGET, action="take traffic anyway (D8)")
        else:
            log("warm-ready", ratio=ratio)

    def warm_ratio(self, cw):
        stat = cw.get_metric_statistics(Namespace="Payments", MetricName="cache_warm_ratio", Dimensions=[{"Name": "cell", "Value": self.a.cell}],
                                        StartTime=time.time() - 120, EndTime=time.time(), Period=60, Statistics=["Minimum"])
        points = sorted(stat["Datapoints"], key=lambda p: p["Timestamp"])
        return points[-1]["Minimum"] if points else 0.0

    def scale_cell(self):
        region = self.region or self.a.target_region
        self.run_document(region, "dr-scale-cell", {"Cell": [self.a.cell], "Percent": ["100"]}, "scale-cell")

    def switch_traffic(self):
        region = self.region or self.a.target_region
        arn = self.a.target_endpoint_groups[region]
        ga = self.client("globalaccelerator", "us-west-2")
        eg = ga.describe_endpoint_group(EndpointGroupArn=arn)["EndpointGroup"]
        if eg["TrafficDialPercentage"] == 100:
            log("skip-traffic", reason="already 100", region=region)
            return
        if self.act("switch-traffic", endpoint_group=arn):
            ga.update_endpoint_group(EndpointGroupArn=arn, TrafficDialPercentage=100)

    def reconcile(self):
        region = self.region or self.a.target_region
        self.run_document(region, "dr-psp-reconcile", {"Cell": [self.a.cell], "WindowMinutes": ["5"]}, "reconcile")

    def run(self):
        steps = [self.confirm, self.fence, self.acquire_lock, self.ensure_compute, self.promote_aurora, self.warm_memorydb,
                 self.scale_cell, self.switch_traffic, self.reconcile]
        for step in steps:
            log("step", name=step.__name__, cell=self.a.cell)
            step()
        log("switched", cell=self.a.cell, region=self.region or self.a.target_region, dry_run=self.a.dry_run)


def parse_args(argv):
    ap = argparse.ArgumentParser(description="DR switch of one cell (D7); fencing runs first")
    ap.add_argument("--cell", required=True)
    ap.add_argument("--run-id", required=True, help="stable per incident, so a re-run resumes the same switch")
    ap.add_argument("--confirmed-by", default="", help="on-call who confirmed the switch")
    ap.add_argument("--name-prefix", required=True, help="naming prefix of the platform, naming.prefix in config/platform.yaml")
    ap.add_argument("--source-region", required=True)
    ap.add_argument("--target-region", required=True)
    ap.add_argument("--fallback-region", required=True)
    ap.add_argument("--lock-region", required=True, help="never the region being failed away from")
    ap.add_argument("--lock-table", help="default: <prefix>-prod-<lock region short>-dr-lock")
    ap.add_argument("--global-cluster", help="default: <prefix>-prod-<cell>-aurora-payments")
    ap.add_argument("--fence-rule-group", help="default: <prefix>-prod-<source region short>-psp-fence")
    ap.add_argument("--source-endpoint-group", required=True)
    ap.add_argument("--target-endpoint-group", action="append", default=[], metavar="REGION=ARN")
    ap.add_argument("--capacity-wait-s", type=int, default=600)
    ap.add_argument("--warm-wait-s", type=int, default=300)
    ap.add_argument("--step-timeout-s", type=int, default=3600)
    ap.add_argument("--poll-s", type=int, default=15)
    ap.add_argument("--dry-run", action="store_true")
    ns = ap.parse_args(argv)
    ns.lock_table = ns.lock_table or f"{ns.name_prefix}-prod-{short(ns.lock_region)}-dr-lock"
    ns.global_cluster = ns.global_cluster or f"{ns.name_prefix}-prod-{ns.cell}-aurora-payments"
    ns.fence_rule_group = ns.fence_rule_group or f"{ns.name_prefix}-prod-{short(ns.source_region)}-psp-fence"
    ns.target_endpoint_groups = dict(p.split("=", 1) for p in ns.target_endpoint_group)
    missing = {ns.target_region, ns.fallback_region} - set(ns.target_endpoint_groups)
    if missing:
        ap.error(f"--target-endpoint-group missing for {sorted(missing)}")
    return ns


def main(argv=None, **kw):
    ns = parse_args(argv if argv is not None else sys.argv[1:])
    try:
        Failover(ns, **kw).run()
    except Refused as exc:
        log("refused", reason=str(exc))
        return EXIT_REFUSED
    except LockHeld as exc:
        log("skip", reason=str(exc))
        return EXIT_LOCK_HELD
    except Exception as exc:  # noqa: BLE001
        # an unreachable control plane must end as a logged failure, never as a traceback
        log("error", error=type(exc).__name__, reason=str(exc))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
