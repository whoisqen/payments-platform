#!/usr/bin/env python3
# Section 23.5: a Claude session works in exactly one environment (CLAUDE_ENV); .claude/mcp/<env>.yaml lists its servers.
import os, re
import _common
from _common import payload, block, ENVS, init_root, guarded, agent_of

MERGE = re.compile(r"merge|delete|force|close")
ISSUE = re.compile(r"issue|project", re.I)


def servers(text, key):
    m = re.search(rf"^\s+{key}:\s*\[(.*?)\]", text, re.M | re.S)
    return [x.strip() for x in m.group(1).split(",") if x.strip()] if m else []


def main():
    p = payload()
    init_root(p)
    env = os.environ.get("CLAUDE_ENV", "dev")
    if env not in ENVS:
        block(f"CLAUDE_ENV={env}: allowed values are {', '.join(ENVS)}")
    if env == "cde-prod":
        block("cde-prod: no MCP; only aggregated metrics exported outside the CDE are available.")
    m = re.match(r"mcp__(.+?)__(.+)$", p.get("tool_name", ""))
    if not m:
        raise SystemExit(0)
    server, tool = m.groups()
    prof = _common.ROOT / ".claude" / "mcp" / f"{env}.yaml"
    if not prof.is_file():
        block(f"no MCP profile for environment {env}")
    text = prof.read_text(encoding="utf-8")
    allowed = servers(text, "read")
    write = servers(text, "write")
    if server in write:
        if MERGE.search(tool):
            block(f"{server}.{tool}: merge, close and delete are never done through MCP; a human merges.")
        # Taking a task moves its issue to In progress in any phase; pull requests wait for the deliver phase.
        if os.environ.get("CLAUDE_PHASE") != "deliver" and not ISSUE.search(tool):
            block(f"{server} is a write server; it is allowed only in the deliver phase (CLAUDE_PHASE=deliver).")
    elif server not in allowed:
        # User-level plugins (memory, charts) are not project servers; only agents are held to the profile.
        project = set(re.findall(r'^\s{4}"([^"]+)":\s*\{', (_common.ROOT / ".mcp.json").read_text(encoding="utf-8"), re.M)) if (_common.ROOT / ".mcp.json").is_file() else set()
        if agent_of(p) or server in project:
            block(f"MCP server {server} is not in the {env} profile (.claude/mcp/{env}.yaml).")


guarded(main)
