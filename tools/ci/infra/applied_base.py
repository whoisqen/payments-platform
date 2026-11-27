#!/usr/bin/env python3
# The newest commit an environment fully converged on: a push run of infra-apply whose <env> apply succeeded, or whose plan found nothing to apply.
import argparse
import json
import re
import subprocess
import sys

SHA = re.compile(r"^[0-9a-f]{40}$")


def converged(jobs, env):
    by_name = {j.get("name"): j.get("conclusion") for j in jobs}
    plan, apply = by_name.get(f"{env} / plan"), by_name.get(f"{env} / apply")
    return apply == "success" or (plan == "success" and apply in (None, "skipped"))


def find_base(runs, jobs_of, env, is_ancestor):
    for run in runs:
        sha = run.get("head_sha", "")
        if run.get("event") != "push" or run.get("status") != "completed" or not SHA.match(sha):
            continue
        # a run on a commit that is no longer on main (force-push) cannot be a diff base
        if converged(jobs_of(run["id"]), env) and is_ancestor(sha):
            return sha
    return None


def gh(*args):
    out = subprocess.run(["gh", "api", *args], capture_output=True, text=True, check=True)
    return out.stdout


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--env", required=True, choices=["dev", "stage", "prod"])
    ap.add_argument("--repo", required=True)
    ap.add_argument("--workflow", default="infra-apply.yml")
    ap.add_argument("--head", default="HEAD")
    ap.add_argument("--max-runs", type=int, default=200)
    ns = ap.parse_args(argv)

    def runs():
        page = 1
        while (page - 1) * 100 < ns.max_runs:
            data = json.loads(gh(f"repos/{ns.repo}/actions/workflows/{ns.workflow}/runs?branch=main&event=push&status=completed&per_page=100&page={page}"))
            batch = data.get("workflow_runs", [])
            yield from batch
            if len(batch) < 100:
                return
            page += 1

    def jobs_of(run_id):
        return json.loads(gh(f"repos/{ns.repo}/actions/runs/{run_id}/jobs?filter=latest&per_page=100")).get("jobs", [])

    def is_ancestor(sha):
        return subprocess.run(["git", "merge-base", "--is-ancestor", sha, ns.head], capture_output=True).returncode == 0

    try:
        print(find_base(runs(), jobs_of, ns.env, is_ancestor) or "none")
    except subprocess.CalledProcessError as e:
        print(f"applied-base: error: {e.stderr.strip()}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
