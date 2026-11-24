#!/usr/bin/env python3
"""Advisory AI review of a pull request. `plan` decides whether to review; `run` builds the request, calls Bedrock and posts one comment."""
import argparse
import json
import os
import re
import secrets
import subprocess
import sys
import urllib.request
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sanitize  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
CONFIG = ROOT / "config" / "ai-review.yaml"
CDE_PATHS = ROOT / "policy" / "cde-paths.yaml"
PROMPT = Path(__file__).resolve().parent / "prompt.md"
HUNK = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@")
SEVERITIES = ("high", "medium", "low")
GIT_NOISE = ("index ", "--- ", "+++ ", "similarity index", "\\ No newline")


def glob_regex(pattern):
    out, i = [], 0
    while i < len(pattern):
        if pattern.startswith("**/", i):
            out.append("(?:.*/)?")
            i += 3
        elif pattern.startswith("**", i):
            out.append(".*")
            i += 2
        elif pattern[i] == "*":
            out.append("[^/]*")
            i += 1
        else:
            out.append(re.escape(pattern[i]))
            i += 1
    return re.compile("^" + "".join(out) + "$")


def matches(path, patterns):
    return any(glob_regex(p).match(path) for p in patterns)


def load_yaml(path):
    return yaml.safe_load(Path(path).read_text(encoding="utf-8")) or {}


def git(*args):
    return subprocess.run(["git", "-C", str(ROOT), *args], check=True, capture_output=True, text=True).stdout


def pr_from_event(path):
    if not path:
        return {"number": None, "title": "(local run)", "body": "", "draft": False, "labels": [], "author": "", "fork": False}
    pr = json.loads(Path(path).read_text(encoding="utf-8")).get("pull_request") or {}
    head_repo = (pr.get("head") or {}).get("repo") or {}
    base_repo = (pr.get("base") or {}).get("repo") or {}
    return {
        "number": pr.get("number"), "title": pr.get("title") or "", "body": pr.get("body") or "",
        "draft": bool(pr.get("draft")), "labels": [lb.get("name") for lb in pr.get("labels") or []],
        "author": (pr.get("user") or {}).get("login") or "",
        # a deleted head repository counts as a fork
        "fork": bool(head_repo.get("fork")) or head_repo.get("full_name") != base_repo.get("full_name"),
    }


def changed_files(base, head):
    out = git("diff", "--name-status", "-z", "--no-renames", f"{base}...{head}").split("\0")
    files = []
    for status, path in zip(out[0::2], out[1::2]):
        files.append((status, path))
    return files


def commit_authors(base, head):
    return {a for a in git("log", "--format=%an", f"{base}..{head}").splitlines() if a}


def skip_reason(pr, files, cfg, role_arn, authors=()):
    skip = cfg["skip"]
    if not role_arn:
        return "AI_REVIEW_ROLE_ARN is not set"
    if pr["fork"]:
        return "pull request comes from a fork"
    if skip.get("draft") and pr["draft"]:
        return "draft pull request"
    labels = set(skip.get("labels") or [])
    if labels & set(pr["labels"]):
        return f"label {sorted(labels & set(pr['labels']))[0]}"
    bots = set(skip.get("authors") or [])
    if pr["author"] in bots or (authors and set(authors) <= bots):
        return "bot author"
    if not [f for f in files if not matches(f[1], skip.get("paths") or [])]:
        return "only documentation, lockfiles, generated or vendored files changed"
    return None


def split_diff(text):
    parts = re.split(r"(?m)^(?=diff --git )", text)
    diffs = {}
    for part in parts:
        m = re.match(r"diff --git a/(.*?) b/(.*)\n", part)
        if m:
            diffs[m.group(2)] = part
    return diffs


def annotate(diff):
    """Prefix each line with its new-file line number; returns the text and the set of numbered lines."""
    out, numbered, new = [], set(), None
    for line in diff.splitlines():
        h = HUNK.match(line)
        if h:
            new = int(h.group(1))
            out.append(line)
        elif new is None:
            if line.startswith("diff --git") or line.startswith(GIT_NOISE):
                continue
            out.append(line)
        elif line.startswith("\\"):
            continue
        elif line.startswith("-"):
            out.append(f"{'':>6} {line}")
        else:
            numbered.add(new)
            out.append(f"{new:>6} {line[:1] or ' '}{line[1:]}")
            new += 1
    return "\n".join(out), numbered


def risk(path, cde, cfg):
    if matches(path, cde):
        return 1000
    if matches(path, cfg.get("high_risk_paths") or []):
        return 500
    return -100 if re.search(r"(^|/)(tests?|__tests__)/|(^|/)test_[^/]*$|_test\.[a-z]+$", path) else 0


def select(diffs, files, cfg, cde):
    """Return (reviewed {path: text, numbered}, omitted paths) honouring the size caps, highest risk first."""
    lim = cfg["limits"]
    skip = cfg["skip"].get("paths") or []
    status = dict((p, s) for s, p in files)
    candidates = []
    for path, diff in diffs.items():
        if matches(path, skip) or "\nBinary files" in diff or "\nGIT binary patch" in diff:
            continue
        text, numbered = annotate(diff)
        if len(text.encode()) > lim["max_file_diff_bytes"]:
            text = text.encode()[:lim["max_file_diff_bytes"]].decode(errors="ignore") + "\n[diff of this file truncated]"
        candidates.append((path, text, numbered))
    total = sum(len(t.encode()) for _, t, _ in candidates)
    ordered = sorted(candidates, key=lambda c: (-risk(c[0], cde, cfg), len(c[1]), c[0]))
    reviewed, omitted, used = {}, [], 0
    for path, text, numbered in ordered:
        size = len(text.encode())
        if total > lim["max_diff_bytes"] and used + size > lim["max_diff_bytes"] and reviewed:
            omitted.append(path)
            continue
        used += size
        reviewed[path] = {"text": text, "numbered": numbered, "cde": matches(path, cde), "status": status.get(path, "M")}
    return reviewed, sorted(omitted), total > lim["max_diff_bytes"]


def build_prompt(cfg, pr, reviewed, omitted, redactor, delim):
    system = PROMPT.read_text(encoding="utf-8").replace("{{DELIM}}", delim).replace("{{MAX_FINDINGS}}", str(cfg["limits"]["max_findings"]))
    body = pr["body"][:cfg["limits"]["max_body_chars"]]
    parts = [f"{delim}-BEGIN", f"title: {redactor.redact(pr['title'])}", f"description:\n{redactor.redact(body)}", ""]
    for path, f in reviewed.items():
        parts.append(f"=== FILE {path} (status {f['status']}){' [CDE]' if f['cde'] else ''} ===")
        parts.append(redactor.redact(f["text"]))
    if omitted:
        parts.append(f"NOT INCLUDED (diff over the size cap): {', '.join(omitted[:50])}")
    parts.append(f"{delim}-END")
    user = "\n".join(parts)
    return system, user


def parse_findings(text, reviewed, max_findings):
    """Return (summary, findings, dropped) from the model reply; findings outside the diff are dropped."""
    m = re.search(r"\{[\s\S]*\}", text or "")
    if not m:
        raise ValueError("the reply holds no JSON object")
    data = json.loads(m.group(0))
    findings, dropped = [], 0
    for f in data.get("findings") or []:
        try:
            path, line = str(f["file"]), int(f["line"])
            sev = str(f.get("severity", "")).lower()
            ok = path in reviewed and line in reviewed[path]["numbered"] and sev in SEVERITIES
        except (KeyError, TypeError, ValueError):
            ok = False
        if not ok:
            dropped += 1
            continue
        findings.append({"file": path, "line": line, "severity": sev, "title": str(f.get("title", ""))[:120],
                         "evidence": str(f.get("evidence", ""))[:1000], "fix": str(f.get("fix", ""))[:1000]})
    findings.sort(key=lambda f: SEVERITIES.index(f["severity"]))
    dropped += max(0, len(findings) - max_findings)
    return str(data.get("summary", ""))[:300], findings[:max_findings], dropped


def clean(text):
    # model output goes into a PR comment: no mentions, no HTML, no card data or secrets
    text = sanitize.redact(text)[0].replace("@", "@​").replace("<", "&lt;")
    return text.replace("\r", "").strip()


def render(cfg, summary, findings, dropped, omitted, truncated, counts, model_id):
    lines = [cfg["comment"]["marker"], "### AI review (advisory)", ""]
    if findings:
        lines.append(f"{len(findings)} finding(s). This review is advisory and does not block the merge.")
        lines.append("")
        for f in findings:
            lines += [f"- **{f['severity']}** `{f['file']}:{f['line']}` {clean(f['title'])}",
                      f"  - Evidence: {clean(f['evidence'])}", f"  - Fix: {clean(f['fix'])}"]
    else:
        lines.append("No findings.")
    if summary and findings:
        lines += ["", clean(summary)]
    notes = []
    if truncated:
        notes.append(f"The diff is over the size cap; only the highest-risk files were reviewed. Not reviewed: {', '.join(f'`{p}`' for p in omitted[:20])}"
                     + (f" and {len(omitted) - 20} more" if len(omitted) > 20 else "") + ".")
    if dropped:
        notes.append(f"{dropped} finding(s) dropped (outside the diff or over the limit).")
    if counts:
        notes.append(f"{sum(counts.values())} secret or card value(s) were redacted before the model saw the diff.")
    lines += [""] + [f"> {n}" for n in notes] + [f"<sub>{model_id}; label `ai-review:skip` turns the review off.</sub>"]
    return "\n".join(lines)


def call_bedrock(cfg, system, user):
    import boto3
    from botocore.config import Config
    m = cfg["model"]
    client = boto3.client("bedrock-runtime", region_name=m["region"],
                          config=Config(read_timeout=m["timeout_seconds"], retries={"max_attempts": 3, "mode": "standard"}))
    resp = client.converse(modelId=m["id"], system=[{"text": system}], messages=[{"role": "user", "content": [{"text": user}]}],
                           inferenceConfig={"maxTokens": m["max_tokens"], "temperature": m["temperature"]})
    return "".join(b.get("text", "") for b in resp["output"]["message"]["content"])


def github(method, path, token, payload=None):
    req = urllib.request.Request(f"https://api.github.com{path}", method=method, data=json.dumps(payload).encode() if payload else None,
                                 headers={"Authorization": f"Bearer {token}", "Accept": "application/vnd.github+json",
                                          "X-GitHub-Api-Version": "2022-11-28", "User-Agent": "ai-review"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read() or "null")


def upsert_comment(repo, number, token, marker, body):
    page = 1
    while True:
        comments = github("GET", f"/repos/{repo}/issues/{number}/comments?per_page=100&page={page}", token)
        for c in comments:
            if marker in (c.get("body") or "") and (c.get("user") or {}).get("type") == "Bot":
                github("PATCH", f"/repos/{repo}/issues/comments/{c['id']}", token, {"body": body})
                return "updated"
        if len(comments) < 100:
            break
        page += 1
    github("POST", f"/repos/{repo}/issues/{number}/comments", token, {"body": body})
    return "created"


def set_output(**kv):
    path = os.environ.get("GITHUB_OUTPUT")
    for k, v in kv.items():
        print(f"{k}={v}")
        if path:
            with open(path, "a", encoding="utf-8") as fh:
                fh.write(f"{k}={v}\n")


def summary(text):
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if path:
        with open(path, "a", encoding="utf-8") as fh:
            fh.write(text + "\n")


def context(args):
    cfg = load_yaml(args.config)
    cde = load_yaml(CDE_PATHS).get("cde_paths") or []
    pr = pr_from_event(args.event)
    files = changed_files(args.base, args.head)
    return cfg, cde, pr, files


def plan(args):
    cfg, cde, pr, files = context(args)
    reason = skip_reason(pr, files, cfg, os.environ.get("AI_REVIEW_ROLE_ARN", "") or args.role_arn, commit_authors(args.base, args.head))
    if reason:
        summary(f"AI review skipped: {reason}.")
    set_output(skip="true" if reason else "false", reason=reason or "", region=cfg["model"]["region"])


def run(args):
    cfg, cde, pr, files = context(args)
    diffs = split_diff(git("diff", "--unified=3", "--no-renames", f"{args.base}...{args.head}"))
    reviewed, omitted, truncated = select(diffs, files, cfg, cde)
    redactor = sanitize.Redactor(redact_emails=cfg["sanitize"]["redact_emails"])
    system, user = build_prompt(cfg, pr, reviewed, omitted, redactor, f"UNTRUSTED-{secrets.token_hex(8)}")
    m = cfg["model"]
    if args.dry_run:
        request = {"modelId": m["id"], "region": m["region"], "inferenceConfig": {"maxTokens": m["max_tokens"], "temperature": m["temperature"]},
                   "system": system, "user": user, "files": list(reviewed), "omitted": omitted, "redacted": {k: int(v) for k, v in redactor.counts.items()}}
        Path(args.dry_run).write_text(json.dumps(request, indent=2) + "\n", encoding="utf-8")
        return 0
    try:
        reply = call_bedrock(cfg, system, user)
        text, findings, dropped = parse_findings(reply, reviewed, cfg["limits"]["max_findings"])
    except Exception as e:  # advisory: an outage or a bad reply must not turn the pull request red
        print(f"::warning::AI review failed: {type(e).__name__}: {str(e)[:300]}")
        summary(f"AI review failed: {type(e).__name__}.")
        return 0
    body = render(cfg, text, findings, dropped, omitted, truncated, dict(redactor.counts), m["id"])
    token = os.environ["GH_TOKEN"]
    result = upsert_comment(os.environ["GITHUB_REPOSITORY"], pr["number"], token, cfg["comment"]["marker"], body)
    summary(f"AI review comment {result}: {len(findings)} finding(s).")
    return 0


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("command", choices=["plan", "run"])
    p.add_argument("--base", default=os.environ.get("BASE_SHA", "origin/main"))
    p.add_argument("--head", default=os.environ.get("HEAD_SHA", "HEAD"))
    p.add_argument("--event", default=os.environ.get("GITHUB_EVENT_PATH"))
    p.add_argument("--config", default=str(CONFIG))
    p.add_argument("--role-arn", default="", help="for local plan runs; CI uses AI_REVIEW_ROLE_ARN")
    p.add_argument("--dry-run", metavar="FILE", help="write the request to FILE and exit without calling AWS or GitHub")
    args = p.parse_args(argv)
    if args.command == "plan":
        plan(args)
        return 0
    return run(args)


if __name__ == "__main__":
    sys.exit(main())
