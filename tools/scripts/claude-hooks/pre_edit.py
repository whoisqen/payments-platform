#!/usr/bin/env python3
# Agent write guard: writes are allowed only inside the agent's own paths (owns) from orchestration.yaml.
# A normal human session (no agent_type, CLAUDE_AGENT unset) is not restricted.
import os, re
import _common
from _common import payload, block, matches, orchestration, agent_of, init_root, guarded, owned

# The guard scripts and the CDE list steer every agent, so no agent may write them.
PROTECTED = ["tools/scripts/claude-hooks/**", "tools/lint/**", "policy/cde-paths.yaml"]


def main():
    p = payload()
    agent = agent_of(p)
    if not agent:
        raise SystemExit(0)
    path = (p.get("tool_input") or {}).get("file_path")
    init_root(p, path if isinstance(path, str) else None)
    r = _common.rel(path) if path else None
    if r is None:
        block(f"agent {agent}: writing outside the repository is forbidden: {path}")
    cfg = orchestration()
    for group in ("humans_only", "ci_only", "integrator_only"):
        if matches(r, cfg[group]):
            block(f"agent {agent}: {r} is in {group}; agents may not write it")
    if matches(r, PROTECTED):
        block(f"agent {agent}: {r} is a guardrail file; only a human edits it")
    if matches(r, ["specs/*/spec.md"]):
        f = _common.ROOT / r
        if f.is_file() and not re.search(r"^status:\s*draft\b", f.read_text(encoding="utf-8"), re.M):
            block(f"agent {agent}: {r} is not in status draft; an approved specification is not edited")
    if matches(r, [f"specs/*/handoffs/{agent}-*.md", "specs/*/progress/T*.md"]):
        raise SystemExit(0)
    owns = cfg["agents"].get(agent)
    if owns is None:
        extra = os.environ.get("CLAUDE_AGENT_PATHS", "")
        owns = [x for x in extra.split(":") if x]
    if not owns:
        block(f"agent {agent}: no owns in .claude/orchestration.yaml and no CLAUDE_AGENT_PATHS from the orchestrator")
    if not (owned(cfg, agent, r) if cfg['agents'].get(agent) else matches(r, owns)):
        block(f"agent {agent}: {r} is outside owns {owns}; write a request to another domain in specs/<spec>/handoffs/{agent}-<to>.md")


guarded(main)
