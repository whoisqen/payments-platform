#!/usr/bin/env python3
import argparse
import re
import sys
from pathlib import Path

DIGEST = re.compile(r"^sha256:[a-f0-9]{64}$")
SERVICES = ["router", "drainer", "scheduler", "locker", "control-center"]
ENVS = ["dev", "stage", "prod"]


def parse(text):
    out = {}
    for raw in text.splitlines():
        line = raw.split("#", 1)[0].rstrip()
        if not line or line == "images:":
            continue
        m = re.match(r"^  ([a-z-]+): (sha256:[a-f0-9]{64})$", line)
        if not m:
            raise ValueError(f"bad images.yaml line: {raw!r}")
        out[m.group(1)] = m.group(2)
    return out


def render(images):
    unknown = set(images) - set(SERVICES)
    if unknown:
        raise ValueError(f"unknown service: {sorted(unknown)}")
    body = "".join(f"  {s}: {images[s]}\n" for s in SERVICES if s in images)
    return "images:\n" + body


def update(current, changes):
    for name, digest in changes.items():
        if name not in SERVICES:
            raise ValueError(f"unknown service: {name}")
        if not DIGEST.match(digest):
            raise ValueError(f"{name}: not a sha256 digest")
    return {**current, **changes}


def promotion_violations(source, before, after):
    # stage and prod take exactly the digest that passed the previous environment
    bad = []
    for name, digest in after.items():
        if before.get(name) != digest and source.get(name) != digest:
            bad.append(f"{name}: {digest} is not the digest of the previous environment")
    return bad


def load(path):
    p = Path(path)
    return parse(p.read_text(encoding="utf-8")) if p.is_file() else {}


def main(argv=None):
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("set")
    s.add_argument("file")
    s.add_argument("pairs", nargs="+", help="service=sha256:...")
    s.add_argument("--dry-run", action="store_true")
    c = sub.add_parser("copy")
    c.add_argument("source")
    c.add_argument("file")
    c.add_argument("--services", help="comma list; default all that differ")
    c.add_argument("--dry-run", action="store_true")
    v = sub.add_parser("verify")
    v.add_argument("source")
    v.add_argument("before")
    v.add_argument("file")
    ns = ap.parse_args(argv)

    if ns.cmd == "verify":
        bad = promotion_violations(load(ns.source), load(ns.before), load(ns.file))
        for b in bad:
            print(f"images-yaml: error: {b}")
        return 1 if bad else 0

    current = load(ns.file)
    if ns.cmd == "set":
        changes = dict(p.split("=", 1) for p in ns.pairs)
    else:
        src = load(ns.source)
        names = ns.services.split(",") if ns.services else list(src)
        changes = {n: src[n] for n in names if n in src}
    new = update(current, changes)
    if new == current:
        print("images-yaml: unchanged")
        return 0
    diff = [n for n in new if current.get(n) != new[n]]
    print(f"images-yaml: {'would change' if ns.dry_run else 'changed'}: {','.join(diff)}")
    if not ns.dry_run:
        Path(ns.file).parent.mkdir(parents=True, exist_ok=True)
        Path(ns.file).write_text(render(new), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
