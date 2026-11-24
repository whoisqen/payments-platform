#!/usr/bin/env python3
"""Advisory AI review of a pull request. `plan` decides whether to review; `run` builds the request, calls Bedrock and posts one comment."""
import argparse
import datetime
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
        return {"number": None, "title": "(local run)", "body": "", "draft": False, "labels": [], "author": "", "fork": False,
                "action": None, "label": None}
    event = json.loads(Path(path).read_text(encoding="utf-8"))
    pr = event.get("pull_request") or {}
    head_repo = (pr.get("head") or {}).get("repo") or {}
    base_repo = (pr.get("base") or {}).get("repo") or {}
    return {
        "number": pr.get("number"), "title": pr.get("title") or "", "body": pr.get("body") or "",
        "draft": bool(pr.get("draft")), "labels": [lb.get("name") for lb in pr.get("labels") or []],
        "author": (pr.get("user") or {}).get("login") or "",
        # a deleted head repository counts as a fork
        "fork": bool(head_repo.get("fork")) or head_repo.get("full_name") != base_repo.get("full_name"),
        "action": event.get("action"), "label": (event.get("label") or {}).get("name"),
    }


def changed_files(base, head):
    # the head is only data here: git diff with no external diff driver and no textconv
    out = git("diff", "--no-ext-diff", "--no-textconv", "--name-status", "-z", "--no-renames", f"{base}...{head}").split("\0")
    files = []
    for status, path in zip(out[0::2], out[1::2]):
        files.append((status, path))
    return files


def blob(sha, path, limit=1_000_000):
    """Text of a file at a commit, read as data; empty when the file is absent."""
    try:
        return git("show", f"{sha}:{path}")[:limit]
    except subprocess.CalledProcessError:
        return ""


def is_secret_manifest(path, shas):
    """A Kubernetes Secret manifest, found in the whole file because `kind: Secret` is often outside the diff context."""
    return path.endswith((".yaml", ".yml", ".tpl")) and any(sanitize.K8S_KIND.search(blob(sha, path)) for sha in shas)


def decide_trigger(action, label, head_sha, last, now, trigger):
    """Return the reason to skip, or None to review. `last` is None or {"sha", "updated_at"} of the previous review comment."""
    if action in (None, "opened", "ready_for_review"):
        return None
    if action == "labeled":
        return None if label == trigger["run_label"] else f"label {label} does not start a review"
    if action in ("synchronize", "reopened"):
        if last is None:
            return None
        if last["sha"] == head_sha:
            return "this head was already reviewed"
        minutes = (now - last["updated_at"]).total_seconds() / 60
        if minutes < trigger["min_minutes_between_reviews"]:
            return f"reviewed {int(minutes)} min ago; add the label {trigger['run_label']} to review now"
        return None
    return f"event {action} does not start a review"


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


def annotate(diff, redactor=None, k8s_secret=False):
    """Prefix each line with its new-file line number; returns the text and the set of numbered lines.

    The raw content is redacted first (every line break is kept, so the numbers stay right), and only then the prefixes are added."""
    items, numbered, new = [], set(), None
    lines = diff.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    for line in (ln.rstrip("\r") for ln in lines):
        h = HUNK.match(line)
        if h:
            new = int(h.group(1))
            items.append(["hunk", line[:h.end()], line[h.end():]])
        elif new is None:
            if not (line.startswith("diff --git") or line.startswith(GIT_NOISE)):
                items.append(["head", "", line])
        elif line.startswith("\\"):
            continue
        elif line.startswith("-"):
            items.append(["del", "", line[1:]])
        else:
            numbered.add(new)
            items.append(["ctx", f"{new:>6} {line[:1] or ' '}", line[1:]])
            new += 1
    if redactor is not None:
        parts = redactor.redact("\n".join(i[2] for i in items), keep_lines=True, k8s_secret=k8s_secret).split("\n")
        if len(parts) != len(items):
            raise RuntimeError("redaction changed the number of lines")
        for item, part in zip(items, parts):
            item[2] = part
    out = []
    for kind, prefix, text in items:
        out.append(f"{'':>6} -{text}" if kind == "del" else prefix + text)
    return "\n".join(out), numbered


def drop_trailing_digits(text):
    """A cut can leave the first digits of a card number: drop a trailing run of 6 or more digits (with separators)."""
    return re.sub(r"(?:\d[\s.\-/_]?){5,}\d[\s.\-/_]?$", "", text)


def cut(text, max_bytes):
    if len(text.encode()) <= max_bytes:
        return text
    return drop_trailing_digits(text.encode()[:max_bytes].decode(errors="ignore")) + "\n[diff of this file truncated]"


def risk(path, cde, cfg):
    if matches(path, cde):
        return 1000
    if matches(path, cfg.get("high_risk_paths") or []):
        return 500
    return -100 if re.search(r"(^|/)(tests?|__tests__)/|(^|/)test_[^/]*$|_test\.[a-z]+$", path) else 0


def select(diffs, files, cfg, cde, redactor=None, is_secret=None):
    """Return (reviewed {path: text, numbered}, omitted paths) honouring the size caps, highest risk first.

    Each diff is redacted before it is cut, so a cut can never split a secret into a form the patterns miss."""
    lim = cfg["limits"]
    skip = cfg["skip"].get("paths") or []
    status = dict((p, s) for s, p in files)
    candidates = []
    for path, diff in diffs.items():
        if matches(path, skip) or "\nBinary files" in diff or "\nGIT binary patch" in diff:
            continue
        text, numbered = annotate(diff, redactor, bool(is_secret and is_secret(path)))
        text = cut(text, lim["max_file_diff_bytes"])
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
    body = drop_trailing_digits(redactor.redact(pr["body"])[:cfg["limits"]["max_body_chars"]])
    parts = [f"{delim}-BEGIN", f"title: {redactor.redact(pr['title'])}", f"description:\n{body}", ""]
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
        findings.append({"file": path, "line": line, "severity": sev, "title": str(f.get("title", ""))[:80],
                         "evidence": str(f.get("evidence", ""))[:300], "fix": str(f.get("fix", ""))[:300]})
    findings.sort(key=lambda f: SEVERITIES.index(f["severity"]))
    dropped += max(0, len(findings) - max_findings)
    return str(data.get("summary", ""))[:160], findings[:max_findings], dropped


MD_IMAGE = re.compile(r"!\[[^\]]*\]\([^)]*\)")
MD_LINK = re.compile(r"\[([^\]]*)\]\([^)]*\)")
URL = re.compile(r"(?i)(?:\b[a-z][a-z0-9+.-]{1,15}://|\bwww\.)\S+")
HEAD_MARK = re.compile(r"<!-- ai-review-head: ([0-9a-f]{40}) -->")
BOT_LOGIN = "github-actions[bot]"


def clean(text):
    """Model output goes into a PR comment: no card data or secrets, no images, links or URLs, no markup, one line."""
    text = " ".join(sanitize.redact(str(text))[0].split())
    text = URL.sub("", MD_LINK.sub(r"\1", MD_IMAGE.sub("", text)))
    text = text.replace("&", "&amp;").replace("\\", "\\\\")
    for ch in "`[]()*_|~#":
        text = text.replace(ch, "\\" + ch)
    return text.replace("<", "&lt;").replace(">", "&gt;").replace("@", "@\u200b").strip()


def code(text):
    """A code span that the text cannot break out of: the fence is one backtick longer than the longest run inside."""
    text = " ".join(str(text).split())
    longest = max((len(r) for r in re.findall(r"`+", text)), default=0)
    fence = "`" * (longest + 1)
    return f"{fence} {text} {fence}" if longest else f"`{text}`"


def render(cfg, summary, findings, dropped, omitted, truncated, model_id, head_sha=""):
    lines = [cfg["comment"]["marker"]] + ([f"<!-- ai-review-head: {head_sha} -->"] if head_sha else []) + ["### AI review (advisory)", ""]
    if findings:
        lines.append(f"{len(findings)} finding(s). This review is advisory and does not block the merge.")
        lines.append("")
        for f in findings:
            lines += [f"- **{f['severity']}** {code(f['file'] + ':' + str(f['line']))} {clean(f['title'])}",
                      f"  - Evidence: {clean(f['evidence'])}", f"  - Fix: {clean(f['fix'])}"]
    else:
        lines.append("No findings.")
    if summary and findings:
        lines += ["", clean(summary)]
    notes = []
    if truncated:
        notes.append(f"The diff is over the size cap; only the highest-risk files were reviewed. Not reviewed: {', '.join(code(p) for p in omitted[:20])}"
                     + (f" and {len(omitted) - 20} more" if len(omitted) > 20 else "") + ".")
    if dropped:
        notes.append(f"{dropped} finding(s) dropped (outside the diff or over the limit).")
    lines += [""] + [f"> {n}" for n in notes] + [f"<sub>{clean(model_id)}; label `ai-review:skip` turns the review off, label `ai-review:run` starts a new one.</sub>"]
    return "\n".join(lines)


class GuardrailBlocked(Exception):
    pass


def converse_args(cfg, system, user):
    """Arguments of the Bedrock Converse call; the guardrail is attached when its id is configured."""
    m = cfg["model"]
    g = m.get("guardrail") or {}
    guardrail_id, version = str(g.get("id") or "").strip(), str(g.get("version") or "").strip()
    args = {"modelId": m["id"], "system": [{"text": system}], "messages": [{"role": "user", "content": [{"text": user}]}],
            "inferenceConfig": {"maxTokens": m["max_tokens"], "temperature": m["temperature"]}}
    if guardrail_id:
        if not version:
            raise ValueError("model.guardrail.version is empty")
        args["guardrailConfig"] = {"guardrailIdentifier": guardrail_id, "guardrailVersion": version, "trace": "disabled"}
    return args


def converse(client, cfg, system, user):
    args = converse_args(cfg, system, user)
    if "guardrailConfig" not in args:
        print("::warning::model.guardrail.id is not set: the request goes to the model without a Bedrock guardrail")
    resp = client.converse(**args)
    if resp.get("stopReason") == "guardrail_intervened":
        raise GuardrailBlocked("the guardrail intervened")
    return "".join(b.get("text", "") for b in resp["output"]["message"]["content"])


def call_bedrock(cfg, system, user):
    import boto3
    from botocore.config import Config
    m = cfg["model"]
    client = boto3.client("bedrock-runtime", region_name=m["region"],
                          config=Config(read_timeout=m["timeout_seconds"], retries={"max_attempts": 3, "mode": "standard"}))
    return converse(client, cfg, system, user)


def github(method, path, token, payload=None):
    req = urllib.request.Request(f"https://api.github.com{path}", method=method, data=json.dumps(payload).encode() if payload else None,
                                 headers={"Authorization": f"Bearer {token}", "Accept": "application/vnd.github+json",
                                          "X-GitHub-Api-Version": "2022-11-28", "User-Agent": "ai-review"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read() or "null")


def find_comment(repo, number, token, marker):
    """Our comment: the marker and the author github-actions[bot]; anyone else's copy of the marker is ignored."""
    page = 1
    while True:
        comments = github("GET", f"/repos/{repo}/issues/{number}/comments?per_page=100&page={page}", token)
        for c in comments:
            if marker in (c.get("body") or "") and (c.get("user") or {}).get("login") == BOT_LOGIN:
                return c
        if len(comments) < 100:
            return None
        page += 1


def last_review(comment):
    """{"sha", "updated_at"} of the previous review, from the head line of its comment and the comment time."""
    if comment is None:
        return None
    m = HEAD_MARK.search(comment.get("body") or "")
    when = datetime.datetime.strptime(comment["updated_at"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
    return {"sha": m.group(1) if m else None, "updated_at": when}


def upsert_comment(repo, number, token, marker, body):
    existing = find_comment(repo, number, token, marker)
    if existing:
        github("PATCH", f"/repos/{repo}/issues/comments/{existing['id']}", token, {"body": body})
        return "updated"
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
    if not reason and pr["action"] in ("synchronize", "reopened"):
        try:
            last = last_review(find_comment(os.environ["GITHUB_REPOSITORY"], pr["number"], os.environ["GH_TOKEN"], cfg["comment"]["marker"]))
        except Exception as e:  # without the last review time the cost limit cannot be applied
            print(f"::warning::cannot read the last review comment: {type(e).__name__}")
            last, reason = None, "the last review comment could not be read"
    else:
        last = None
    reason = reason or decide_trigger(pr["action"], pr["label"], args.head, last, datetime.datetime.now(datetime.timezone.utc), cfg["trigger"])
    if reason:
        summary(f"AI review skipped: {reason}.")
    set_output(skip="true" if reason else "false", reason=reason or "", region=cfg["model"]["region"])


def run(args):
    cfg, cde, pr, files = context(args)
    m = cfg["model"]
    redactor = sanitize.Redactor(redact_emails=cfg["sanitize"]["redact_emails"])
    try:
        diffs = split_diff(git("diff", "--no-ext-diff", "--no-textconv", "--unified=3", "--no-renames", f"{args.base}...{args.head}"))
        reviewed, omitted, truncated = select(diffs, files, cfg, cde, redactor, lambda path: is_secret_manifest(path, (args.base, args.head)))
        system, user = build_prompt(cfg, pr, reviewed, omitted, redactor, f"UNTRUSTED-{secrets.token_hex(8)}")
        reply = call_bedrock(cfg, system, user)
        text, findings, dropped = parse_findings(reply, reviewed, cfg["limits"]["max_findings"])
    except Exception as e:  # advisory: an outage or a bad reply must not turn the pull request red; the message may echo input, so only the type is logged
        print(f"::warning::AI review failed: {type(e).__name__}")
        summary(f"AI review failed: {type(e).__name__}.")
        return 0
    body = render(cfg, text, findings, dropped, omitted, truncated, m["id"], args.head if re.fullmatch(r"[0-9a-f]{40}", args.head) else "")
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
    args = p.parse_args(argv)
    if args.command == "plan":
        plan(args)
        return 0
    return run(args)


if __name__ == "__main__":
    sys.exit(main())
