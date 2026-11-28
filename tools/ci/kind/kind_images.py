#!/usr/bin/env python3
"""Image set of the kind commit stage: the digest built in this run, else the digest dev runs now.

  kind_images.py --registry REGISTRY/PREFIX [--digests digests.json] [--images deploy/envs/dev/images.yaml] [--local-repo pay.local]

Prints one line per service: `<service> <registry ref by digest> <local repository> <local tag>`; the job pulls
each ref, tags it locally, loads it into kind and passes the local name to helmfile. With --values it prints the
--state-values-set argument instead. Exit 1 and a message when a service has no digest.
"""
import argparse
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import images_yaml  # noqa: E402

SERVICES = ("router", "drainer", "scheduler", "locker", "control-center", "smoke")
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


def local_tag(digest):
    # kind load goes through docker save, which may not keep the registry digest, so pods use a tag
    return digest.split(":", 1)[1][:16]


def render_lines(registry, local_repo, digests):
    return "".join(f"{s} {registry}/{s}@{digests[s]} {local_repo}/{s} {local_tag(digests[s])}\n" for s in SERVICES)


def render_values(local_repo, digests):
    pairs = []
    for s in SERVICES:
        pairs += [f"images.{s}.repository={local_repo}/{s}", f"images.{s}.tag={local_tag(digests[s])}"]
    return ",".join(pairs) + "\n"


def main(argv=None, out=None):
    out = sys.stdout if out is None else out
    ap = argparse.ArgumentParser()
    ap.add_argument("--registry", required=True)
    ap.add_argument("--digests", default="")
    ap.add_argument("--images", default="deploy/envs/dev/images.yaml")
    ap.add_argument("--local-repo", default="pay.local")
    ap.add_argument("--values", action="store_true", help="print the helmfile --state-values-set argument")
    ns = ap.parse_args(argv)
    if not REGISTRY.match(ns.registry) or not REGISTRY.match(ns.local_repo):
        print("kind-images: bad registry", file=sys.stderr)
        return 2
    built = {}
    if ns.digests and Path(ns.digests).is_file():
        # the artifact is untrusted input: only known services with a well-formed digest are taken
        raw = json.loads(Path(ns.digests).read_text(encoding="utf-8"))
        built = {k: v for k, v in raw.items() if k in SERVICES and isinstance(v, str)} if isinstance(raw, dict) else {}
    digests, missing = resolve(built, images_yaml.load(ns.images))
    if missing:
        print("kind-images: no digest for " + ", ".join(missing), file=sys.stderr)
        return 1
    out.write(render_values(ns.local_repo, digests) if ns.values else render_lines(ns.registry, ns.local_repo, digests))
    return 0


if __name__ == "__main__":
    sys.exit(main())
