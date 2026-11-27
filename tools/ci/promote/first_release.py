#!/usr/bin/env python3
# The first v* tag: prod needs a tag in gated.revision before its first rollout, so v0.1.0 is cut from the commit whose prod digests stage verified.
import argparse
import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import images_yaml  # noqa: E402

FIRST = "v0.1.0"
PROD, STAGE = "deploy/envs/prod/images.yaml", "deploy/envs/stage/images.yaml"


class FirstReleaseError(Exception):
    pass


def decide(tags, prod, stage_history, on_main, only_if_first=False):
    if any(t.startswith("v") for t in tags):
        if only_if_first:
            return {"version": None, "bump": "none"}
        raise FirstReleaseError(f"a v* tag already exists ({sorted(tags)[0]}); later releases come from prod-rollout-complete")
    if not on_main:
        raise FirstReleaseError("the commit is not on main")
    if not prod:
        raise FirstReleaseError(f"{PROD} has no digests at this commit; promote stage to prod first")
    # promote.yml opens the prod pull request only after the stage checks passed, so every prod digest must have run in stage
    unverified = sorted(f"{s}: {d}" for s, d in prod.items() if d not in stage_history)
    if unverified:
        raise FirstReleaseError("digests that never ran in stage: " + ", ".join(unverified))
    return {"version": FIRST, "bump": "first"}


def notes(sha, prod):
    rows = [f"## {FIRST}", "", f"First release: the commit {sha[:7]} whose prod digests passed stage verification.", ""]
    rows += [f"- {s}: `{d}`" for s, d in sorted(prod.items())]
    return "\n".join(rows) + "\n"


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True)


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--sha", required=True)
    ap.add_argument("--main", default="origin/main")
    ap.add_argument("--if-first", action="store_true", help="print bump none instead of failing when a v* tag exists")
    ap.add_argument("--changelog-out")
    ns = ap.parse_args(argv)
    try:
        tags = git("tag", "--list", "v[0-9]*").stdout.split()
        on_main = git("merge-base", "--is-ancestor", ns.sha, ns.main).returncode == 0
        shown = git("show", f"{ns.sha}:{PROD}")
        prod = images_yaml.parse(shown.stdout) if shown.returncode == 0 else {}
        history = set(images_yaml.DIGEST_ANY.findall(git("log", "-p", "--format=", ns.sha, "--", STAGE).stdout))
        out = decide(tags, prod, history, on_main, ns.if_first)
        if out["bump"] != "none" and ns.changelog_out:
            Path(ns.changelog_out).write_text(notes(ns.sha, prod), encoding="utf-8")
        print(json.dumps(out))
    except (FirstReleaseError, ValueError) as e:
        print(f"first-release: error: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
