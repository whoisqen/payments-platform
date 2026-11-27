"""Lambda entry point of the standby failover: the Route 53 health check alarm of the working region promotes the standby data stores.

Configuration comes from environment variables set by infra/modules/dr-failover; one incident is one run id, so a repeated alarm resumes the same switch.
"""
import json
import os
import sys
import time

import failover

DONE = (0, failover.EXIT_LOCK_HELD)
# seconds kept free before the Lambda timeout; used without a context (local run)
MARGIN_SECONDS, DEFAULT_BUDGET_SECONDS = 60, 840


def run_id(event):
    # SNS delivers the alarm as a JSON string; StateChangeTime is stable for one incident
    for record in event.get("Records", []):
        message = json.loads(record["Sns"]["Message"])
        if message.get("NewStateValue") == "ALARM":
            return "hc-" + message["StateChangeTime"]
    return None


def argv_for(env, incident, cell, max_wait):
    argv = ["--auto", "--cell", cell, "--run-id", f"{incident}-{cell}", "--name-prefix", env["NAME_PREFIX"], "--env", env["ENVIRONMENT"],
            "--source-region", env["SOURCE_REGION"], "--target-region", env["TARGET_REGION"], "--lock-table", env["LOCK_TABLE"],
            "--fence-rule-group", env["FENCE_RULE_GROUP"], "--deny-policy-arn", env.get("DENY_POLICY_ARN", ""), "--build-id", incident,
            "--max-wait", str(max(0, int(max_wait)))]
    writer = json.loads(env.get("SWITCH_WRITER_CLASSES") or "{}").get(cell)
    if writer:
        argv += ["--writer-class", writer]
    if env.get("COMPUTE_BUILD_URL"):
        argv += ["--compute-build-url", env["COMPUTE_BUILD_URL"], "--compute-build-secret", env["COMPUTE_BUILD_SECRET"]]
    return argv


def handler(event, context):
    incident = run_id(event)
    if incident is None:
        return {"status": "ignored"}
    env = os.environ
    budget = context.get_remaining_time_in_millis() / 1000 if context is not None else DEFAULT_BUDGET_SECONDS
    deadline = time.monotonic() + budget - MARGIN_SECONDS
    cells = json.loads(env["CELLS"])
    # pass 1 waits for nothing: the compute build and the writers of every cluster start together
    results = {cell: failover.main(argv_for(env, incident, cell, 0)) for cell in cells}
    # pass 2 waits for each writer in turn and promotes; the later writers are usually ready by then
    for cell in cells:
        if results[cell] == failover.EXIT_PENDING:
            results[cell] = failover.main(argv_for(env, incident, cell, deadline - time.monotonic()))
    # the compute build is owned by its workflow (apply, Argo CD, wait for the Applications); the Lambda only dispatches it
    print(json.dumps({"event": "failover-finished", "results": results}, sort_keys=True))
    pending = sorted(c for c, v in results.items() if v == failover.EXIT_PENDING)
    failed = sorted(c for c, v in results.items() if v not in DONE and v != failover.EXIT_PENDING)
    if failed or pending:
        # an error makes Lambda retry the event; the retry resumes the same switch under the same run ids
        raise RuntimeError(f"failover failed for {failed}, pending for {pending}")
    return {"status": "done", "results": results}


if __name__ == "__main__":
    print(handler(json.load(sys.stdin), None))
