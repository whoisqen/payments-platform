#!/usr/bin/env python3
"""Failover and failback of the warm standby region.

failover (--mode failover): the standby region already runs compute and Route 53 moves the traffic; this script fences the working region as far
as it answers, promotes the Aurora global clusters and lets the standby region write to DynamoDB.
failback (--mode failback): planned return to the working region after it is rebuilt; always needs --confirmed-by (a human approves, a person
or an agent may run the command).
"""
import argparse
import json
import sys
import time

FENCE_SID = "sid:900001"
FENCE_RULE = f'drop tcp any any -> any any (msg:"dr fence"; {FENCE_SID}; rev:1;)'
EXIT_REFUSED, EXIT_LOCK_HELD = 2, 3
MAX_FAILBACK_LAG_MS = 1000
RECONCILE_WINDOW_MINUTES = 5


def short(region):
    # eu-central-1 -> euc1, the region short code of the naming scheme
    a, b, c = region.split("-")
    return f"{a}{b[0]}{c}"


class Refused(Exception):
    pass


class LockHeld(Exception):
    pass


def error_code(exc):
    return getattr(exc, "response", {}).get("Error", {}).get("Code", "")


def log(event, **fields):
    print(json.dumps({"event": event, "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), **fields}, sort_keys=True), flush=True)


def aws_client(service, region):
    import boto3  # imported late so the unit tests need no boto3

    return boto3.client(service, region_name=region)


class Switch:
    def __init__(self, args, client=aws_client, sleep=time.sleep, now=time.monotonic):
        self.a = args
        self.client = client
        self.sleep = sleep
        self.now = now

    def act(self, step, **fields):
        log(("would-" if self.a.dry_run else "do-") + step, cell=self.a.cell, run_id=self.a.run_id, **fields)
        return not self.a.dry_run

    @property
    def key(self):
        return {"pk": {"S": f"dr-switch#{self.a.cell}"}}

    def confirm(self):
        if self.a.auto:
            # the Route 53 health check alarm of the working region is the confirmation (owner decision for the warm standby)
            log("confirmed", confirmed_by="route53-health-check", run_id=self.a.run_id)
            return
        if not self.a.confirmed_by:
            raise Refused("no confirmation: pass --confirmed-by with the approver (failback always needs a human approval)")
        log("confirmed", confirmed_by=self.a.confirmed_by, run_id=self.a.run_id)

    def fence_rules(self):
        nf = self.client("network-firewall", self.a.source_region)
        group = nf.describe_rule_group(RuleGroupName=self.a.fence_rule_group, Type="STATEFUL")
        return nf, group, group["RuleGroup"]["RulesSource"].get("RulesString", "")

    def write_rules(self, nf, group, rules):
        nf.update_rule_group(UpdateToken=group["UpdateToken"], RuleGroupName=self.a.fence_rule_group, Type="STATEFUL",
                             RuleGroup={"RulesSource": {"RulesString": rules}, "StatefulRuleOptions": {"RuleOrder": "STRICT_ORDER"}})

    def fence(self):
        # A failed region may not answer its own control plane; Aurora keeps the old writer from rejoining as a writer.
        try:
            nf, group, rules = self.fence_rules()
            if FENCE_SID not in rules and self.act("fence-firewall", rule_group=self.a.fence_rule_group):
                self.write_rules(nf, group, (rules + "\n" + FENCE_RULE).strip())
            log("fenced", region=self.a.source_region, cell=self.a.cell)
        except Exception as exc:  # noqa: BLE001
            log("fence-unverified", region=self.a.source_region, reason=str(exc), cell=self.a.cell)

    def unfence(self):
        nf, group, rules = self.fence_rules()
        if FENCE_SID in rules and self.act("unfence-firewall", rule_group=self.a.fence_rule_group):
            self.write_rules(nf, group, "\n".join(line for line in rules.splitlines() if FENCE_SID not in line).strip())

    def acquire_lock(self):
        if not self.act("acquire-lock", table=self.a.lock_table):
            return
        ddb = self.client("dynamodb", self.a.target_region)
        try:
            ddb.update_item(TableName=self.a.lock_table, Key=self.key, UpdateExpression="SET run_id = :r",
                            ConditionExpression="attribute_not_exists(pk) OR run_id = :r",
                            ExpressionAttributeValues={":r": {"S": self.a.run_id}})
        except Exception as exc:
            if error_code(exc) == "ConditionalCheckFailedException":
                raise LockHeld(f"switch lock of {self.a.cell} is held by another run") from exc
            raise

    def member(self, rds, region):
        gc = rds.describe_global_clusters(GlobalClusterIdentifier=self.a.global_cluster)["GlobalClusters"][0]
        member = next((m for m in gc["GlobalClusterMembers"] if f":{region}:" in m["DBClusterArn"]), None)
        if member is None:
            raise Refused(f"no member of {self.a.global_cluster} in {region}")
        return member

    def promote_aurora(self):
        rds = self.client("rds", self.a.target_region)
        member = self.member(rds, self.a.target_region)
        if member["IsWriter"]:
            log("skip-promote", reason="already writer", region=self.a.target_region)
            return
        # promotion is the point of no return and happens in exactly one region
        if self.act("promote-aurora", global_cluster=self.a.global_cluster, region=self.a.target_region):
            rds.failover_global_cluster(GlobalClusterIdentifier=self.a.global_cluster, TargetDbClusterIdentifier=member["DBClusterArn"], AllowDataLoss=True)

    def allow_dynamodb_writes(self):
        # The IAM policy denies writes to the merchant-to-cell map in the standby region; the new version drops the promoted region.
        arn = self.a.deny_policy_arn
        if not arn:
            return
        iam = self.client("iam", self.a.target_region)
        current = iam.get_policy(PolicyArn=arn)["Policy"]["DefaultVersionId"]
        doc = iam.get_policy_version(PolicyArn=arn, VersionId=current)["PolicyVersion"]["Document"]
        doc = json.loads(doc) if isinstance(doc, str) else doc
        marker = f":dynamodb:{self.a.target_region}:"
        for st in doc["Statement"]:
            res = st["Resource"] if isinstance(st["Resource"], list) else [st["Resource"]]
            st["Resource"] = [r for r in res if marker not in r]
        doc["Statement"] = [st for st in doc["Statement"] if st["Resource"]]
        if not doc["Statement"]:
            # IAM requires a statement; deny nothing real
            doc["Statement"] = [{"Effect": "Deny", "Action": "dynamodb:PutItem", "Resource": "arn:aws:dynamodb:*:000000000000:table/none"}]
        if self.act("allow-dynamodb-writes", region=self.a.target_region, policy=arn):
            # IAM keeps at most five versions of a policy: drop the oldest non-default one first
            versions = [v for v in iam.list_policy_versions(PolicyArn=arn).get("Versions", []) if not v["IsDefaultVersion"]]
            if len(versions) >= 4:
                iam.delete_policy_version(PolicyArn=arn, VersionId=min(versions, key=lambda v: v["CreateDate"])["VersionId"])
            # the previous version is kept in the lock record: failback sets it as default again
            self.client("dynamodb", self.a.target_region).update_item(
                TableName=self.a.lock_table, Key=self.key, UpdateExpression="SET deny_version = :v", ExpressionAttributeValues={":v": {"S": current}})
            iam.create_policy_version(PolicyArn=arn, PolicyDocument=json.dumps(doc), SetAsDefault=True)

    def reconcile(self):
        # PSP reconciliation is done by people with the alert OrphanPaymentWebhooks and its runbook: charges lost to replication lag show up as
        # webhooks for payments the database does not know. The window of data that may be missing ends at the promotion.
        end = time.time()
        log("reconcile-window", cell=self.a.cell, run_id=self.a.run_id, minutes=RECONCILE_WINDOW_MINUTES,
            start=time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(end - RECONCILE_WINDOW_MINUTES * 60)), end=time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(end)))

    # failback ---------------------------------------------------------------------------------------------------------------------------
    def switchover_aurora(self):
        # The working region must be back as a replicating secondary with a small lag; otherwise a switchover back would lose data.
        rds = self.client("rds", self.a.source_region)
        member = self.member(rds, self.a.source_region)
        if member["IsWriter"]:
            raise Refused(f"{self.a.source_region} is already the writer of {self.a.global_cluster}")
        cw = self.client("cloudwatch", self.a.source_region)
        stat = cw.get_metric_statistics(Namespace="AWS/RDS", MetricName="AuroraGlobalDBReplicationLag",
                                        Dimensions=[{"Name": "DBClusterIdentifier", "Value": member["DBClusterArn"].split(":")[-1]}],
                                        StartTime=time.time() - 300, EndTime=time.time(), Period=60, Statistics=["Maximum"])
        points = sorted(stat["Datapoints"], key=lambda p: p["Timestamp"])
        lag = points[-1]["Maximum"] if points else None
        if lag is None or lag > MAX_FAILBACK_LAG_MS:
            raise Refused(f"replication lag to {self.a.source_region} is {lag} ms, the limit is {MAX_FAILBACK_LAG_MS} ms")
        if self.act("switchover-aurora", global_cluster=self.a.global_cluster, region=self.a.source_region):
            # planned switchover: no data loss allowed
            rds.failover_global_cluster(GlobalClusterIdentifier=self.a.global_cluster, TargetDbClusterIdentifier=member["DBClusterArn"], AllowDataLoss=False)

    def deny_standby_writes(self):
        if not self.a.deny_policy_arn:
            return
        ddb = self.client("dynamodb", self.a.target_region)
        item = ddb.get_item(TableName=self.a.lock_table, Key=self.key, ConsistentRead=True).get("Item", {})
        version = item.get("deny_version", {}).get("S")
        if not version:
            raise Refused("the lock record holds no earlier deny policy version; restore the deny policy by hand")
        if self.act("deny-dynamodb-writes", region=self.a.target_region, policy=self.a.deny_policy_arn, version=version):
            self.client("iam", self.a.target_region).set_default_policy_version(PolicyArn=self.a.deny_policy_arn, VersionId=version)

    def release_lock(self):
        if self.act("release-lock", table=self.a.lock_table):
            self.client("dynamodb", self.a.target_region).delete_item(TableName=self.a.lock_table, Key=self.key)

    def run(self):
        if self.a.mode == "failover":
            steps = [self.confirm, self.fence, self.acquire_lock, self.promote_aurora, self.allow_dynamodb_writes, self.reconcile]
        else:
            steps = [self.confirm, self.switchover_aurora, self.deny_standby_writes, self.unfence, self.release_lock]
        for step in steps:
            log("step", name=step.__name__, cell=self.a.cell)
            step()
        log("switched", mode=self.a.mode, cell=self.a.cell, dry_run=self.a.dry_run)


def parse_args(argv):
    ap = argparse.ArgumentParser(description="Failover or failback of one cell or the locker of the warm standby region")
    ap.add_argument("--mode", choices=["failover", "failback"], default="failover")
    ap.add_argument("--cell", required=True)
    ap.add_argument("--run-id", required=True, help="stable per incident, so a re-run resumes the same switch")
    ap.add_argument("--auto", action="store_true", help="started by the health check alarm: no confirmation (failover only)")
    ap.add_argument("--confirmed-by", default="", help="approver of the switch; always required for failback")
    ap.add_argument("--name-prefix", required=True, help="naming prefix of the platform, naming.prefix in config/platform.yaml")
    ap.add_argument("--env", default="prod")
    ap.add_argument("--source-region", required=True, help="working region")
    ap.add_argument("--target-region", required=True, help="standby region")
    ap.add_argument("--lock-table", help="default: <prefix>-<env>-<target short>-dr-lock")
    ap.add_argument("--global-cluster", help="default: <prefix>-<env>-<source short>-aurora-<cell>")
    ap.add_argument("--fence-rule-group", help="default: <prefix>-<env>-<source short>-psp-fence")
    ap.add_argument("--deny-policy-arn", default="", help="IAM policy that denies DynamoDB writes in the standby region")
    ap.add_argument("--dry-run", action="store_true")
    ns = ap.parse_args(argv)
    if ns.mode == "failback" and ns.auto:
        ap.error("failback is never automatic")
    ns.lock_table = ns.lock_table or f"{ns.name_prefix}-{ns.env}-{short(ns.target_region)}-dr-lock"
    ns.global_cluster = ns.global_cluster or f"{ns.name_prefix}-{ns.env}-{short(ns.source_region)}-aurora-{ns.cell}"
    ns.fence_rule_group = ns.fence_rule_group or f"{ns.name_prefix}-{ns.env}-{short(ns.source_region)}-psp-fence"
    return ns


def main(argv=None, **kw):
    ns = parse_args(argv if argv is not None else sys.argv[1:])
    try:
        Switch(ns, **kw).run()
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
