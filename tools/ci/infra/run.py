#!/usr/bin/env python3
# Plans and applies the stacks of stacks.py level by level; every stack gets the credentials of its own role through GitHub OIDC.
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SHA = re.compile(r"^[0-9a-f]{40}$")
CRED_VARS = ("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN", "AWS_PROFILE")


class RunError(Exception):
    pass


def component(stack):
    return stack.rstrip("/").split("/")[-1]


def role_arn(cfg, env, kind, stack=None):
    account = str(cfg["accounts"]["shared_services"])
    prefix = cfg["naming"]["prefix"]
    name = f"{prefix}-{env}-glob-tf-plan" if kind == "plan" else f"{prefix}-{env}-glob-tf-apply-{component(stack)}"
    return f"arn:aws:iam::{account}:role/{name}"


def plan_file(stack):
    return stack.replace("/", "__") + ".tfplan"


def github_token():
    url, bearer = os.environ.get("ACTIONS_ID_TOKEN_REQUEST_URL"), os.environ.get("ACTIONS_ID_TOKEN_REQUEST_TOKEN")
    if not url or not bearer:
        raise RunError("no GitHub OIDC token: the job needs permissions id-token: write")
    req = urllib.request.Request(url + "&" + urllib.parse.urlencode({"audience": "sts.amazonaws.com"}),
                                 headers={"Authorization": f"Bearer {bearer}"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)["value"]


class Runner:
    def __init__(self, workdir, fetch_token=github_token, execute=None, parallel=4, log=print):
        self.workdir = Path(workdir)
        self.fetch_token = fetch_token
        self.execute = execute or self._execute
        self.parallel = parallel
        self.log = log

    @staticmethod
    def _execute(cmd, env, out_path):
        with open(out_path, "w", encoding="utf-8") as out:
            return subprocess.run(cmd, env=env, stdout=out, stderr=subprocess.STDOUT, cwd=ROOT).returncode

    def env_for(self, role, stack):
        # a fresh token per stack: the SDK assumes the role itself, so no long-lived key ever exists
        fd, path = tempfile.mkstemp(dir=self.workdir, prefix="oidc-")
        with os.fdopen(fd, "w") as f:
            f.write(self.fetch_token())
        env = {k: v for k, v in os.environ.items() if k not in CRED_VARS}
        env.update(AWS_ROLE_ARN=role, AWS_WEB_IDENTITY_TOKEN_FILE=path,
                   AWS_ROLE_SESSION_NAME=f"infra-apply-{component(stack)}"[:64], TF_IN_AUTOMATION="1")
        return env

    def terragrunt(self, stack, role, args, tag, log=None):
        cmd = ["terragrunt", "run", "--non-interactive", "--working-dir", stack, "--", *args]
        log = log or self.workdir / f"{plan_file(stack)}.{tag}.log"
        code = self.execute(cmd, self.env_for(role, stack), log)
        return code, log

    def each(self, fn, stacks):
        with ThreadPoolExecutor(max_workers=max(1, self.parallel)) as pool:
            return dict(zip(stacks, pool.map(fn, stacks), strict=True))


def emit(log, stack, path):
    text = Path(path).read_text(encoding="utf-8", errors="replace") if Path(path).is_file() else ""
    log(f"::group::{stack}\n{text.rstrip()}\n::endgroup::")


def plan(runner, cfg, stacks_doc, out, sha, apply_now=False):
    env, deps = stacks_doc["env"], stacks_doc["deps"]
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    status, totals = {}, {}
    for level in stacks_doc["levels"]:
        todo = []
        for s in level:
            upstream = [status.get(d) for d in deps.get(s, [])]
            # a plan made before its changed upstream is applied would carry mock or stale outputs
            if not apply_now and any(u in ("changes", "deferred") for u in upstream):
                status[s] = "deferred"
            else:
                todo.append(s)

        def one(s):
            role = role_arn(cfg, env, "apply" if apply_now else "plan", s)
            code, log = runner.terragrunt(s, role, ["plan", "-input=false", "-detailed-exitcode", f"-out={(out / plan_file(s)).resolve()}"], "plan")
            emit(runner.log, s, log)
            if code == 2:
                # the readable plan travels with the binary one: it is what the approver of the environment reviews
                text = out / f"{plan_file(s)}.txt"
                runner.terragrunt(s, role, ["show", "-no-color", str((out / plan_file(s)).resolve())], "show", text)
                totals[s] = plan_totals(text)
                return "changes"
            return "none" if code == 0 else "failed"

        status.update(runner.each(one, todo))
        if apply_now:
            def apply_one(s):
                code, log = runner.terragrunt(s, role_arn(cfg, env, "apply", s), ["apply", "-input=false", str((out / plan_file(s)).resolve())], "apply")
                emit(runner.log, s, log)
                return "applied" if code == 0 else "failed"

            status.update(runner.each(apply_one, [s for s in level if status.get(s) == "changes"]))
        if any(status.get(s) == "failed" for s in level):
            break
    manifest = {"env": env, "sha": sha, "levels": stacks_doc["levels"], "status": status, "plans": totals}
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return manifest


def apply(runner, cfg, bundle, sha):
    bundle = Path(bundle)
    manifest = json.loads((bundle / "manifest.json").read_text(encoding="utf-8"))
    if manifest.get("sha") != sha:
        raise RunError(f"the plan was made for {manifest.get('sha')}, this run is {sha}")
    env, status = manifest["env"], manifest["status"]
    for level in manifest["levels"]:
        todo = [s for s in level if status.get(s) == "changes"]
        for s in todo:
            if not (bundle / plan_file(s)).is_file():
                raise RunError(f"the reviewed plan of {s} is missing")

        def one(s):
            code, log = runner.terragrunt(s, role_arn(cfg, env, "apply", s), ["apply", "-input=false", str((bundle / plan_file(s)).resolve())], "apply")
            emit(runner.log, s, log)
            return "applied" if code == 0 else "failed"

        status.update(runner.each(one, todo))
        if any(status.get(s) == "failed" for s in level):
            break
    return manifest


def plan_totals(path):
    text = Path(path).read_text(encoding="utf-8", errors="replace") if Path(path).is_file() else ""
    hits = re.findall(r"^Plan: .*$", text, re.M)
    return hits[-1] if hits else ""


def summary(manifest, title):
    rows = [f"### {title}", "", "| stack | result | plan |", "|---|---|---|"]
    plans = manifest.get("plans", {})
    for level in manifest["levels"]:
        rows += [f"| `{s}` | {manifest['status'].get(s, 'not run')} | {plans.get(s, '')} |" for s in level]
    return "\n".join(rows) + "\n"


def outcome(manifest):
    st = manifest["status"].values()
    return {"changes": "changes" in st, "deferred": "deferred" in st, "failed": "failed" in st}


def write_github(manifest, title):
    for var, text in (("GITHUB_STEP_SUMMARY", summary(manifest, title)),
                      ("GITHUB_OUTPUT", "".join(f"{k}={str(v).lower()}\n" for k, v in outcome(manifest).items()))):
        if os.environ.get(var):
            with open(os.environ[var], "a", encoding="utf-8") as f:
                f.write(text)


def main(argv=None):
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("plan")
    p.add_argument("--stacks", required=True, help="output of stacks.py")
    p.add_argument("--out", required=True)
    p.add_argument("--apply-now", action="store_true", help="apply each plan before the next level (dev)")
    a = sub.add_parser("apply")
    a.add_argument("--bundle", required=True)
    for x in (p, a):
        x.add_argument("--sha", required=True)
        x.add_argument("--parallel", type=int, default=4)
    ns = ap.parse_args(argv)
    try:
        if not SHA.match(ns.sha):
            raise RunError("--sha must be a full commit sha")
        import yaml

        cfg = yaml.safe_load((ROOT / "config/platform.yaml").read_text(encoding="utf-8"))
        workdir = Path(tempfile.mkdtemp(prefix="infra-"))
        runner = Runner(workdir, parallel=ns.parallel)
        if ns.cmd == "plan":
            doc = json.loads(Path(ns.stacks).read_text(encoding="utf-8"))
            manifest = plan(runner, cfg, doc, ns.out, ns.sha, ns.apply_now)
            write_github(manifest, f"{doc['env']}: {'plan and apply' if ns.apply_now else 'plan'}")
        else:
            manifest = apply(runner, cfg, ns.bundle, ns.sha)
            write_github(manifest, f"{manifest['env']}: apply of the reviewed plan")
            if outcome(manifest)["deferred"]:
                print("::error::stacks were deferred behind a changed upstream; use Re-run all jobs (not failed jobs) so they are planned against the applied state")
                return 1
        return 1 if outcome(manifest)["failed"] else 0
    except (RunError, OSError, KeyError, ValueError) as e:
        print(f"run: error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
