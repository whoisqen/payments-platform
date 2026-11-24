#!/usr/bin/env python3
"""Picks the revision a smoke-green repository_dispatch promotes.

  select_revision.py --action smoke-green-dev --payload-env PAYLOAD [--main origin/main]

The payload is untrusted: it is read from an environment variable, parsed as JSON and validated
before any value reaches git. The synced revision is the one in `revisions` that is an ancestor of main
(the newest one if several are). Prints the 40-hex sha; exit 1 and a message on a bad payload.
"""
import argparse
import json
import os
import re
import subprocess
import sys

SHA = re.compile(r"[0-9a-f]{40}")
ACTION = re.compile(r"^smoke-green-([a-z]+)$")


class PayloadError(Exception):
    pass


def validate(action, raw):
    m = ACTION.match(action or "")
    if not m:
        raise PayloadError(f"unexpected event action {action!r}")
    try:
        payload = json.loads(raw or "")
    except ValueError as e:
        raise PayloadError(f"client_payload is not JSON: {e}")
    if not isinstance(payload, dict):
        raise PayloadError("client_payload is not an object")
    if payload.get("environment") != m.group(1):
        raise PayloadError(f"environment {payload.get('environment')!r} does not match the event {action!r}")
    revisions = payload.get("revisions")
    if not isinstance(revisions, list) or not revisions:
        raise PayloadError("revisions must be a non-empty list")
    for r in revisions:
        if not isinstance(r, str) or not SHA.fullmatch(r):
            raise PayloadError("every revision must be a full 40-hex sha")
    return list(dict.fromkeys(revisions))


def synced(revisions, is_ancestor, newest_first):
    """is_ancestor(sha) -> bool; newest_first(shas) -> the shas ordered newest first."""
    on_main = [r for r in revisions if is_ancestor(r)]
    if not on_main:
        raise PayloadError("no revision is an ancestor of main")
    return newest_first(on_main)[0]


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True)


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--action", required=True)
    ap.add_argument("--payload-env", required=True, help="name of the environment variable holding the JSON payload")
    ap.add_argument("--main", default="origin/main")
    ns = ap.parse_args(argv)
    try:
        revisions = validate(ns.action, os.environ.get(ns.payload_env, ""))

        def is_ancestor(sha):
            return git("merge-base", "--is-ancestor", sha, ns.main).returncode == 0

        def newest_first(shas):
            out = git("log", "--no-walk=sorted", "--format=%H", *shas, "--")
            return out.stdout.split() or shas

        print(synced(revisions, is_ancestor, newest_first))
    except PayloadError as e:
        print(f"select-revision: error: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
