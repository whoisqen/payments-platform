#!/usr/bin/env python3
"""Failover and failback of the hot standby region (ADR-0019).

failover (--mode failover): fences the working region as far as it answers, promotes the Aurora global clusters and lets the standby region
write to DynamoDB. Fallback for a standby that has lost its compute (--writer-class, --compute-build-url): the run first dispatches the CI
build of the standby compute, adds a writer to each secondary without an instance and waits for it before the promotion; with --await-build
it waits for the compute build as well.
failback (--mode failback): planned return to the working region after it is rebuilt; always needs --confirmed-by (a human approves, a person
or an agent may run the command).
"""
import argparse
import json
import sys
import time
import urllib.request

FENCE_SID = "sid:900001"
FENCE_RULE = f'drop tcp any any -> any any (msg:"dr fence"; {FENCE_SID}; rev:1;)'
EXIT_REFUSED, EXIT_LOCK_HELD, EXIT_PENDING = 2, 3, 4
MAX_FAILBACK_LAG_MS = 1000
RECONCILE_WINDOW_MINUTES = 5
POLL_SECONDS = 30
WRITER_SUFFIX = "-writer"
# a dispatch whose run never showed up may be repeated after this many seconds
REDISPATCH_SECONDS = 300


def short(region):
    # eu-central-1 -> euc1, the region short code of the naming scheme
    a, b, c = region.split("-")
    return f"{a}{b[0]}{c}"


class Refused(Exception):
    pass


class LockHeld(Exception):
    pass


class Pending(Exception):
    pass


def build_title(env, build_id):
    # must equal run-name of .github/workflows/dr-compute-build.yml: the dispatch API returns no run id
    return f"dr-compute-build {env} {build_id}"


def http_json(method, url, token, body=None):
    if not url.startswith("https://"):
        raise ValueError("the compute build URL must use https")
    req = urllib.request.Request(url, data=None if body is None else json.dumps(body).encode(), method=method, headers={
        "Authorization": f"Bearer {token}", "Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "dr-failover", "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        raw = resp.read()
    return json.loads(raw) if raw else {}


def error_code(exc):
    return getattr(exc, "response", {}).get("Error", {}).get("Code", "")


def log(event, **fields):
    print(json.dumps({"event": event, "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), **fields}, sort_keys=True), flush=True)


def aws_client(service, region):
    import boto3  # imported late so the unit tests need no boto3
    from botocore.config import Config

    # a failed region often hangs instead of refusing; short timeouts keep the run inside the Lambda budget
    return boto3.client(service, region_name=region, config=Config(connect_timeout=5, read_timeout=20, retries={"max_attempts": 3, "mode": "standard"}))


class Switch:
    def __init__(self, args, client=aws_client, sleep=time.sleep, now=time.monotonic, http=http_json):
        self.a = args
        self.client = client
        self.sleep = sleep
        self.now = now
        self.http = http
        self.deadline = now() + args.max_wait
        self.promoted = False
        self.token = None

    def act(self, step, **fields):
        log(("would-" if self.a.dry_run else "do-") + step, cell=self.a.cell, run_id=self.a.run_id, **fields)
        return not self.a.dry_run

    @property
    def key(self):
        return {"pk": {"S": f"dr-switch#{self.a.cell}"}}

    # the deny policy is shared by all cells: the version before the failover is also kept once for every cell
    DENY_KEY = {"pk": {"S": "dr-deny-policy"}}

    def confirm(self):
        if self.a.auto:
            # the Route 53 health check alarm of the working region is the confirmation (owner decision for the hot standby)
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

    def wait_or_pending(self, what):
        # bounded wait: a run that hits its deadline ends as pending and a re-run with the same run id resumes here
        if self.now() + POLL_SECONDS > self.deadline:
            raise Pending(what)
        self.sleep(POLL_SECONDS)

    def member(self, rds, region):
        gc = rds.describe_global_clusters(GlobalClusterIdentifier=self.a.global_cluster)["GlobalClusters"][0]
        member = next((m for m in gc["GlobalClusterMembers"] if f":{region}:" in m["DBClusterArn"]), None)
        if member is None:
            raise Refused(f"no member of {self.a.global_cluster} in {region}")
        return member

    def target_cluster(self, rds):
        member = self.member(rds, self.a.target_region)
        return member, member["DBClusterArn"].split(":")[-1]

    # compute fallback -------------------------------------------------------------------------------------------------------------------
    @property
    def build_lock(self):
        return {"pk": {"S": f"dr-compute-build#{self.a.build_id}"}}

    def build_token(self):
        if self.token is None:
            arn = self.a.compute_build_secret
            raw = self.client("secretsmanager", arn.split(":")[3]).get_secret_value(SecretId=arn)["SecretString"]
            try:
                parsed = json.loads(raw)
            except ValueError:
                parsed = raw
            self.token = str(parsed["token"] if isinstance(parsed, dict) else parsed).strip()
        return self.token

    def build_run(self):
        url = self.a.compute_build_url.rsplit("/dispatches", 1)[0] + "/runs?event=workflow_dispatch&per_page=50"
        title = build_title(self.a.env, self.a.build_id)
        return next((r for r in self.http("GET", url, self.build_token()).get("workflow_runs", []) if r.get("display_title") == title), None)

    def start_compute_build(self):
        # EKS and MemoryDB are the longest steps and need no Aurora writer, so the build starts before the writers
        if not self.a.compute_build_url:
            return
        if not self.act("dispatch-compute-build", build_id=self.a.build_id, region=self.a.target_region):
            return
        run = self.build_run()
        if run is not None:
            log("skip-dispatch-compute-build", reason="run exists", run=run.get("html_url", ""), cell=self.a.cell)
            return
        stamp = int(time.time())
        try:
            # one dispatch per incident for all cells; a dispatch whose run never appeared may be repeated later
            self.client("dynamodb", self.a.target_region).update_item(
                TableName=self.a.lock_table, Key=self.build_lock, UpdateExpression="SET dispatched_at = :t",
                ConditionExpression="attribute_not_exists(dispatched_at) OR dispatched_at < :stale",
                ExpressionAttributeValues={":t": {"N": str(stamp)}, ":stale": {"N": str(stamp - REDISPATCH_SECONDS)}})
        except Exception as exc:
            if error_code(exc) == "ConditionalCheckFailedException":
                log("skip-dispatch-compute-build", reason="dispatched by another run", cell=self.a.cell)
                return
            raise
        try:
            self.http("POST", self.a.compute_build_url, self.build_token(), {
                "ref": self.a.compute_build_ref, "inputs": {"environment": self.a.env, "region": self.a.target_region, "incident": self.a.build_id,
                                                         "trigger": "switch", "confirm": f"switch {self.a.env}"}})
        except Exception:
            # the marker must not hold back the retry of a dispatch that did not happen
            self.client("dynamodb", self.a.target_region).update_item(TableName=self.a.lock_table, Key=self.build_lock, UpdateExpression="REMOVE dispatched_at")
            raise
        log("compute-build-dispatched", build_id=self.a.build_id, cell=self.a.cell)

    def add_writer(self):
        # a headless secondary has no instance that could become the writer, so one is added before the promotion
        if not self.a.writer_class:
            return
        rds = self.client("rds", self.a.target_region)
        member, cluster_id = self.target_cluster(rds)
        if member["IsWriter"]:
            log("skip-add-writer", reason="already writer", cluster=cluster_id)
            return
        cluster = rds.describe_db_clusters(DBClusterIdentifier=cluster_id)["DBClusters"][0]
        if cluster.get("DBClusterMembers"):
            log("skip-add-writer", reason="cluster has an instance", cluster=cluster_id)
            return
        if self.act("add-writer", cluster=cluster_id, instance_class=self.a.writer_class):
            try:
                rds.create_db_instance(DBInstanceIdentifier=cluster_id + WRITER_SUFFIX, DBClusterIdentifier=cluster_id, Engine=cluster["Engine"],
                                       DBInstanceClass=self.a.writer_class, PromotionTier=0, Tags=cluster.get("TagList", []))
            except Exception as exc:
                if error_code(exc) != "DBInstanceAlreadyExists":
                    raise

    def wait_writer(self):
        if not self.a.writer_class:
            return
        rds = self.client("rds", self.a.target_region)
        member, cluster_id = self.target_cluster(rds)
        if member["IsWriter"]:
            return
        if self.a.dry_run:
            log("would-wait-writer", cluster=cluster_id, cell=self.a.cell)
            return
        while True:
            found = rds.describe_db_instances(Filters=[{"Name": "db-cluster-id", "Values": [cluster_id]}])["DBInstances"]
            states = {i["DBInstanceIdentifier"]: i["DBInstanceStatus"] for i in found}
            if "available" in states.values():
                log("writer-available", cluster=cluster_id, cell=self.a.cell)
                return
            self.wait_or_pending(f"no available instance in {cluster_id} yet: {states}")

    def wait_compute_build(self):
        if not (self.a.compute_build_url and self.a.await_build):
            return
        if self.a.dry_run:
            log("would-wait-compute-build", build_id=self.a.build_id)
            return
        while True:
            run = self.build_run()
            if run is not None and run.get("status") == "completed":
                if run.get("conclusion") != "success":
                    raise RuntimeError(f"compute build {run.get('html_url', '')} ended with {run.get('conclusion')}")
                log("compute-build-done", run=run.get("html_url", ""), build_id=self.a.build_id)
                return
            self.wait_or_pending(f"compute build {self.a.build_id} is {'not visible' if run is None else run.get('status')}")

    def promote_aurora(self):
        rds = self.client("rds", self.a.target_region)
        member = self.member(rds, self.a.target_region)
        if member["IsWriter"]:
            log("skip-promote", reason="already writer", region=self.a.target_region)
            return
        # promotion is the point of no return and happens in exactly one region
        if self.act("promote-aurora", global_cluster=self.a.global_cluster, region=self.a.target_region):
            rds.failover_global_cluster(GlobalClusterIdentifier=self.a.global_cluster, TargetDbClusterIdentifier=member["DBClusterArn"], AllowDataLoss=True)
        self.promoted = True

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
        if not any(marker in r for st in doc["Statement"] for r in (st["Resource"] if isinstance(st["Resource"], list) else [st["Resource"]])):
            # a re-run must not overwrite the deny version that failback restores
            log("skip-allow-dynamodb-writes", reason="already allowed", region=self.a.target_region)
            return
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
            ddb = self.client("dynamodb", self.a.target_region)
            for key in (self.key, self.DENY_KEY):
                ddb.update_item(TableName=self.a.lock_table, Key=key, UpdateExpression="SET deny_version = :v", ExpressionAttributeValues={":v": {"S": current}})
            iam.create_policy_version(PolicyArn=arn, PolicyDocument=json.dumps(doc), SetAsDefault=True)

    def reconcile(self):
        # PSP reconciliation is done by people with the alert OrphanPaymentWebhooks and its runbook: charges lost to replication lag show up as
        # webhooks for payments the database does not know. The window of data that may be missing ends at the promotion.
        if not self.promoted:
            log("skip-reconcile-window", reason="promoted by an earlier run", cell=self.a.cell)
            return
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
        version = None
        for key in (self.key, self.DENY_KEY):
            item = ddb.get_item(TableName=self.a.lock_table, Key=key, ConsistentRead=True).get("Item", {})
            version = item.get("deny_version", {}).get("S")
            if version:
                break
        if not version:
            raise Refused("the lock record holds no earlier deny policy version; restore the deny policy by hand")
        iam = self.client("iam", self.a.target_region)
        if iam.get_policy(PolicyArn=self.a.deny_policy_arn)["Policy"]["DefaultVersionId"] == version:
            log("skip-deny-dynamodb-writes", reason="deny version already default", version=version)
            return
        if self.act("deny-dynamodb-writes", region=self.a.target_region, policy=self.a.deny_policy_arn, version=version):
            iam.set_default_policy_version(PolicyArn=self.a.deny_policy_arn, VersionId=version)

    def release_lock(self):
        if self.act("release-lock", table=self.a.lock_table):
            self.client("dynamodb", self.a.target_region).delete_item(TableName=self.a.lock_table, Key=self.key)

    def run(self):
        if self.a.mode == "failover":
            steps = [self.confirm, self.fence, self.acquire_lock, self.start_compute_build, self.add_writer, self.wait_writer, self.promote_aurora,
                     self.allow_dynamodb_writes, self.reconcile, self.wait_compute_build]
        else:
            steps = [self.confirm, self.switchover_aurora, self.deny_standby_writes, self.unfence, self.release_lock]
        started = self.now()
        for step in steps:
            log("step", name=step.__name__, cell=self.a.cell)
            begun = self.now()
            try:
                step()
            finally:
                log("step-done", name=step.__name__, cell=self.a.cell, seconds=round(self.now() - begun, 1))
        log("switched", mode=self.a.mode, cell=self.a.cell, dry_run=self.a.dry_run, seconds=round(self.now() - started, 1))


def parse_args(argv):
    ap = argparse.ArgumentParser(description="Failover or failback of one cell or the locker of the hot standby region")
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
    ap.add_argument("--writer-class", default="", help="compute fallback: instance class of the writer added to a secondary without an instance")
    ap.add_argument("--compute-build-url", default="", help="compute fallback: GitHub workflow dispatch URL of dr-compute-build.yml")
    ap.add_argument("--compute-build-secret", default="", help="Secrets Manager ARN of the token for the compute build dispatch")
    ap.add_argument("--compute-build-ref", default="main", help="git ref the compute build runs from")
    ap.add_argument("--build-id", default="", help="incident id shared by all cells, one compute build per id (default: --run-id)")
    ap.add_argument("--await-build", action="store_true", help="wait until the compute build has finished")
    ap.add_argument("--max-wait", type=float, default=3600, help="seconds the run may wait for writers and the build before it ends as pending")
    ap.add_argument("--dry-run", action="store_true")
    ns = ap.parse_args(argv)
    if ns.mode == "failback" and ns.auto:
        ap.error("failback is never automatic")
    if ns.compute_build_url and not ns.compute_build_secret:
        ap.error("--compute-build-url needs --compute-build-secret")
    ns.build_id = ns.build_id or ns.run_id
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
    except Pending as exc:
        log("pending", reason=str(exc))
        return EXIT_PENDING
    except Exception as exc:  # noqa: BLE001
        # an unreachable control plane must end as a logged failure, never as a traceback
        log("error", error=type(exc).__name__, reason=str(exc))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
