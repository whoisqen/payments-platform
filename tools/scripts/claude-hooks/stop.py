#!/usr/bin/env python3
# Section 11 (Stop, SubagentStop): an agent does not finish with changes outside its owns or with red pre-commit checks.
# The owns check here is the real boundary: pre_edit.py cannot see writes made through Bash.
import shutil, subprocess
import _common
from _common import payload, block, init_root, agent_of, matches, orchestration, owned, guarded

PROTECTED = ["tools/scripts/claude-hooks/**", "tools/lint/**", "policy/cde-paths.yaml"]


def git(*args):
    out = subprocess.run(["git", *args, "-z"], cwd=_common.ROOT, capture_output=True, text=True).stdout
    return [x for x in out.split("\0") if x]


def main():
    p = payload()
    init_root(p)
    root = _common.ROOT
    if p.get("stop_hook_active") or not (root / ".git").exists():
        raise SystemExit(0)
    changed = sorted(set(git("diff", "--name-only", "HEAD") + git("ls-files", "-o", "--exclude-standard")))
    agent = agent_of(p)
    if agent and changed:
        cfg = orchestration()
        extra = [x for x in __import__("os").environ.get("CLAUDE_AGENT_PATHS", "").split(":") if x]
        bad = []
        for f in changed:
            if matches(f, [f"specs/*/handoffs/{agent}-*.md", "specs/*/progress/T*.md"]):
                continue
            if any(matches(f, cfg[g]) for g in ("humans_only", "ci_only", "integrator_only")) or matches(f, PROTECTED):
                bad.append(f)
            elif cfg["agents"].get(agent):
                if not owned(cfg, agent, f):
                    bad.append(f)
            elif not matches(f, extra):
                bad.append(f)
        if bad:
            block(f"agent {agent} changed files outside its owns: {bad[:20]}; revert them or write a handoff request.")
    files = [f for f in changed if (root / f).is_file()]
    if not files or not (root / ".pre-commit-config.yaml").exists() or not shutil.which("pre-commit"):
        raise SystemExit(0)
    try:
        r = subprocess.run(["pre-commit", "run", "--files", *files], cwd=root, capture_output=True, text=True, timeout=840)
    except subprocess.TimeoutExpired:
        block("pre-commit timed out; run it manually and fix the failures.")
    if r.returncode:
        block("pre-commit has failing checks:\n" + r.stdout[-4000:] + r.stderr[-2000:])


guarded(main)
