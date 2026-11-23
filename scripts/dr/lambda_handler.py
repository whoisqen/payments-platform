"""Lambda entry point of the warm standby failover: the Route 53 health check alarm of the working region promotes the standby data stores.

Configuration comes from environment variables set by infra/modules/dr-failover; one incident is one run id, so a repeated alarm resumes the same switch.
"""
import json
import os
import sys

import failover


def run_id(event):
    # SNS delivers the alarm as a JSON string; StateChangeTime is stable for one incident
    for record in event.get("Records", []):
        message = json.loads(record["Sns"]["Message"])
        if message.get("NewStateValue") == "ALARM":
            return "hc-" + message["StateChangeTime"]
    return None


def handler(event, _context):
    incident = run_id(event)
    if incident is None:
        return {"status": "ignored"}
    env = os.environ
    results = {}
    for cell in json.loads(env["CELLS"]):
        argv = ["--mode", "warm", "--auto", "--cell", cell, "--run-id", f"{incident}-{cell}", "--name-prefix", env["NAME_PREFIX"],
                "--source-region", env["SOURCE_REGION"], "--target-region", env["TARGET_REGION"], "--fallback-region", env["FALLBACK_REGION"],
                "--lock-region", env["TARGET_REGION"], "--lock-table", env["LOCK_TABLE"], "--global-cluster", env["GLOBAL_CLUSTER_PATTERN"].format(cell=cell),
                "--fence-rule-group", env["FENCE_RULE_GROUP"], "--deny-policy-arn", env.get("DENY_POLICY_ARN", "")]
        results[cell] = failover.main(argv)
    print(json.dumps({"event": "failover-finished", "results": results}, sort_keys=True))
    if any(code not in (0, failover.EXIT_LOCK_HELD) for code in results.values()):
        # a failed cell must surface in the Lambda error metric and be retried by the next alarm evaluation
        raise RuntimeError(f"failover failed for {sorted(c for c, v in results.items() if v not in (0, failover.EXIT_LOCK_HELD))}")
    return {"status": "done", "results": results}


if __name__ == "__main__":
    print(handler(json.load(sys.stdin), None))
