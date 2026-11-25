#!/usr/bin/env python3
"""Writes the .env of docker/compose: one image reference by digest per service, plus per-run keys.

  compose_env.py --registry REGISTRY/PREFIX [--digests digests.json] [--images deploy/envs/dev/images.yaml] [--keys]

A service built in this run takes its new digest; the others take the digest dev runs now.
Exit 1 and a message when a service has neither.
"""
import argparse
import json
import re
import secrets
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import images_yaml  # noqa: E402

SERVICES = ("router", "drainer", "scheduler", "locker")
REGISTRY = re.compile(r"^[a-z0-9.-]+(:[0-9]+)?(/[a-z0-9._-]+)*$")


def resolve(built, running):
    out, missing = {}, []
    for s in SERVICES:
        d = next((x for x in (built.get(s), running.get(s)) if isinstance(x, str) and images_yaml.DIGEST.match(x)), None)
        if d:
            out[s] = d
        else:
            missing.append(s)
    return out, missing


def render(registry, digests, keys=None):
    lines = [f"{s.upper()}_IMAGE={registry}/{s}@{digests[s]}" for s in SERVICES]
    for k, v in (keys or {}).items():
        lines.append(f"{k}={v}")
    return "\n".join(lines) + "\n"


def main(argv=None, out=None):
    out = sys.stdout if out is None else out
    ap = argparse.ArgumentParser()
    ap.add_argument("--registry", required=True)
    ap.add_argument("--digests", default="")
    ap.add_argument("--images", default="deploy/envs/dev/images.yaml")
    ap.add_argument("--keys", action="store_true", help="add ADMIN_API_KEY and LOCKER_MASTER_KEY generated now")
    ns = ap.parse_args(argv)
    if not REGISTRY.match(ns.registry):
        print("compose-env: bad registry", file=sys.stderr)
        return 2
    built = {}
    if ns.digests and Path(ns.digests).is_file():
        # the artifact is untrusted input: only known services with a well-formed digest are taken
        raw = json.loads(Path(ns.digests).read_text(encoding="utf-8"))
        built = {k: v for k, v in raw.items() if k in SERVICES and isinstance(v, str)} if isinstance(raw, dict) else {}
    digests, missing = resolve(built, images_yaml.load(ns.images))
    if missing:
        print("compose-env: no digest for " + ", ".join(missing), file=sys.stderr)
        return 1
    keys = {"ADMIN_API_KEY": secrets.token_hex(24), "LOCKER_MASTER_KEY": secrets.token_hex(32)} if ns.keys else None
    out.write(render(ns.registry, digests, keys))
    return 0


if __name__ == "__main__":
    sys.exit(main())
