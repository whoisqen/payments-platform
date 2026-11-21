#!/usr/bin/env python3
# Section 27.1: no AI co-authorship marks in commits or PRs; agents never push or merge.
# Production and CDE mutations are denied on the parsed command, because permission prefix rules miss wrapped forms.
import re, shlex
from _common import payload, block, agent_of, guarded

AI = [r"co-authored-by:.*(claude|anthropic)", r"generated with .*claude", r"claude\.com/claude-code",
      r"claude\.ai/code", r"noreply@anthropic\.com"]
MUT = {
    "terraform": {"apply", "destroy", "import", "taint", "untaint"},
    "terragrunt": {"apply", "destroy", "run-all", "import"},
    "kubectl": {"apply", "delete", "exec", "patch", "scale", "edit", "replace", "rollout", "drain", "create",
                "cordon", "uncordon", "taint", "annotate", "label", "set", "cp"},
    "helm": {"install", "upgrade", "uninstall", "rollback"},
}
AWS_VERB = re.compile(r"^(delete|put|create|update|modify|attach|detach|remove|disable|enable|terminate|run|start|stop|"
                      r"send|invoke|deregister|register|revoke|authorize|reboot|release)(-|$)")
READERS = {"cat", "less", "more", "head", "tail", "grep", "rg", "source", ".", "cp", "sed", "awk", "xxd", "strings"}
SECRET = re.compile(r"(^|/)\.env(\.|$)|\.aws(/|$)|\.kube(/|$)")
SEPS = ("&&", "||", ";", "|", "&")


def git_sub(tokens):
    i = 1
    while i < len(tokens) and tokens[i].startswith("-"):
        i += 2 if tokens[i] in ("-c", "-C", "--git-dir", "--work-tree", "--namespace") else 1
    return tokens[i] if i < len(tokens) else ""


def denied(raw, s, agent):
    # Infrastructure mutations are blocked only for subagents; the owner-directed main session may run them.
    head = s[0]
    if head in MUT:
        if any(t.startswith("cde-") or "=cde-" in t for t in raw):
            return "cde-* target"
        if agent and (MUT[head] & set(s[1:]) or (head == "terragrunt" and any("apply" in t for t in s[1:]))):
            return f"{head} mutation"
    if head == "aws":
        if any(t.startswith("cde-") or "=cde-" in t for t in raw):
            return "cde-* AWS profile"
        rest = s[1:]
        if agent and (any(AWS_VERB.match(t) for t in rest) or (rest[:1] == ["s3"] and {"rm", "cp", "mv", "sync"} & set(rest))):
            return "mutating aws call"
    if head in READERS and any(SECRET.search(t) for t in s[1:]):
        return "secret file read"
    return None


def main():
    p = payload()
    cmd = (p.get("tool_input") or {}).get("command", "")
    # Heredoc bodies are data, not commands; every other newline separates commands.
    cmd = re.sub(r"<<-?\s*(['\"]?)(\w+)\1[^\n]*\n.*?\n\s*\2(?=\n|$)", "", cmd, flags=re.S)
    cmd = cmd.replace("\n", " ; ")
    try:
        tokens = shlex.split(cmd)
    except ValueError:
        tokens = cmd.split()
    segs, cur = [], []
    for t in tokens:
        if t in SEPS:
            segs.append(cur); cur = []
        elif t.endswith(";") and len(t) > 1:
            cur.append(t[:-1]); segs.append(cur); cur = []
        else:
            cur.append(t)
    segs.append(cur)
    agent = agent_of(p)
    for raw in segs:
        k = 0
        while k < len(raw) and re.match(r"^\w+=", raw[k]):
            k += 1
        s = raw[k:]
        while s and s[0] in ("env", "sudo", "command", "nohup", "time"):
            s = s[1:]
        if not s:
            continue
        head = s[0]
        text = " ".join(s)
        if head == "git":
            sub = git_sub(s)
            if sub == "commit":
                blob = text
                for i, t in enumerate(s[:-1]):
                    if t in ("-F", "--file"):
                        try:
                            blob += open(s[i + 1], encoding="utf-8", errors="ignore").read()
                        except OSError:
                            pass
                if any(re.search(x, blob, re.I) for x in AI):
                    block("Forbidden: AI co-authorship marks in a commit (section 27.1). Remove the trailer or signature.")
            if agent and sub == "push":
                block("Agents may not run git push (section 11).")
            if agent and "-C" in s[1:3]:
                block("Agents may not run git -C (section 11).")
        elif head == "gh":
            if re.match(r"gh\s+pr\s+(create|edit)\b", text) and any(re.search(x, text, re.I) for x in AI):
                block("Forbidden: AI co-authorship marks in a PR (section 27.1).")
            if re.match(r"gh\s+pr\s+merge\b", text) or (s[1:2] == ["api"] and "merge" in text):
                block("Agents never merge (CLAUDE.md); a human merges the PR.")
        why = denied(raw, s, agent)
        if why:
            block(f"Denied by pre_bash: {why}. Agents never mutate infrastructure, the CDE or production, or read secrets.")


guarded(main)
