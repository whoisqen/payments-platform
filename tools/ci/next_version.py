#!/usr/bin/env python3
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TAG = re.compile(r"^v(\d+)\.(\d+)\.(\d+)$")
HEADER = re.compile(r"^(?P<type>[a-z]+)(?:\((?P<scope>[^)]+)\))?(?P<bang>!)?: (?P<summary>.+)$")
SECTIONS = [("breaking", "Breaking changes"), ("feat", "Features"), ("fix", "Fixes"), ("perf", "Performance"),
            ("revert", "Reverts"), ("other", "Other changes")]
SEP, END = "\x1f", "\x1e"


def parse_commit(sha, subject, body):
    m = HEADER.match(subject.strip())
    if not m:
        return {"sha": sha, "type": "other", "scope": None, "summary": subject.strip(), "breaking": False}
    breaking = bool(m.group("bang")) or bool(re.search(r"^BREAKING[ -]CHANGE:", body, re.M))
    return {"sha": sha, "type": m.group("type"), "scope": m.group("scope"), "summary": m.group("summary"), "breaking": breaking}


def bump_for(commits):
    if any(c["breaking"] for c in commits):
        return "major"
    if any(c["type"] == "feat" for c in commits):
        return "minor"
    # every prod rollout gets a tag, so commits of other types still raise the patch number
    return "patch"


def next_version(last_tag, commits):
    m = TAG.match(last_tag) if last_tag else None
    if last_tag and not m:
        raise ValueError(f"not a version tag: {last_tag}")
    major, minor, patch = (int(x) for x in m.groups()) if m else (0, 0, 0)
    bump = bump_for(commits)
    if bump == "major":
        major, minor, patch = major + 1, 0, 0
    elif bump == "minor":
        minor, patch = minor + 1, 0
    else:
        patch += 1
    return f"v{major}.{minor}.{patch}", bump


def changelog(version, commits):
    lines = [f"## {version}", ""]
    for key, title in SECTIONS:
        if key == "breaking":
            rows = [c for c in commits if c["breaking"]]
        elif key == "other":
            rows = [c for c in commits if not c["breaking"] and c["type"] not in {"feat", "fix", "perf", "revert"}]
        else:
            rows = [c for c in commits if not c["breaking"] and c["type"] == key]
        if not rows:
            continue
        lines += [f"### {title}", ""]
        for c in rows:
            scope = f"**{c['scope']}**: " if c["scope"] else ""
            lines.append(f"- {scope}{c['summary']} ({c['sha'][:7]})")
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def parse_log(raw):
    commits = []
    for rec in raw.split(END):
        rec = rec.strip("\n")
        if not rec:
            continue
        sha, subject, body = (rec.split(SEP) + ["", ""])[:3]
        commits.append(parse_commit(sha, subject, body))
    return commits


def git_log(last_tag, head):
    rng = f"{last_tag}..{head}" if last_tag else head
    fmt = f"%H{SEP}%s{SEP}%b{END}"
    out = subprocess.run(["git", "log", "--no-merges", f"--format={fmt}", rng], cwd=ROOT, capture_output=True, text=True, check=True)
    return out.stdout


def latest_tag():
    out = subprocess.run(["git", "tag", "--list", "v*", "--sort=-v:refname"], cwd=ROOT, capture_output=True, text=True, check=True)
    for t in out.stdout.split():
        if TAG.match(t):
            return t
    return None


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--head", default="HEAD")
    ap.add_argument("--last-tag", help="override the latest v* tag, none for a first release")
    ap.add_argument("--log-file", help="read the git log from this file instead of running git")
    ap.add_argument("--changelog-out")
    ns = ap.parse_args(argv)
    last = latest_tag() if ns.last_tag is None else (None if ns.last_tag == "none" else ns.last_tag)
    raw = Path(ns.log_file).read_text(encoding="utf-8") if ns.log_file else git_log(last, ns.head)
    commits = parse_log(raw)
    if not commits and last:
        print(json.dumps({"version": last, "bump": "none", "previous": last, "commits": 0}))
        return 0
    version, bump = next_version(last, commits)
    if ns.changelog_out:
        Path(ns.changelog_out).write_text(changelog(version, commits), encoding="utf-8")
    print(json.dumps({"version": version, "bump": bump, "previous": last, "commits": len(commits)}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
