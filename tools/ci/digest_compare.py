#!/usr/bin/env python3
import argparse
import json
import re
import sys
from pathlib import Path

DIGEST = re.compile(r"^sha256:[a-f0-9]{64}$")


def metadata_digest(meta):
    d = meta.get("containerimage.digest")
    if not isinstance(d, str) or not DIGEST.match(d):
        raise ValueError("metadata file has no valid containerimage.digest")
    return d


def compare(rebuilt, reference):
    # a missing reference means the image was never built from this source, so there is nothing to compare
    mismatches, skipped = [], []
    for name, digest in sorted(rebuilt.items()):
        ref = reference.get(name)
        if ref is None:
            skipped.append(name)
        elif ref != digest:
            mismatches.append((name, ref, digest))
    return mismatches, skipped


def main(argv=None):
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    m = sub.add_parser("metadata")
    m.add_argument("file")
    c = sub.add_parser("compare")
    c.add_argument("--rebuilt", required=True, help="JSON {service: digest} from the clean rebuild")
    c.add_argument("--reference", required=True, help="JSON {service: digest} of the images built incrementally")
    ns = ap.parse_args(argv)
    if ns.cmd == "metadata":
        print(metadata_digest(json.loads(Path(ns.file).read_text(encoding="utf-8"))))
        return 0
    rebuilt = json.loads(Path(ns.rebuilt).read_text(encoding="utf-8"))
    reference = json.loads(Path(ns.reference).read_text(encoding="utf-8"))
    mismatches, skipped = compare(rebuilt, reference)
    for n in skipped:
        print(f"digest-compare: warning: {n} has no reference digest")
    for n, ref, got in mismatches:
        print(f"::error::digest-compare: {n} rebuilt {got} but the incremental build gave {ref}")
    print(f"digest-compare: {len(mismatches)} mismatch(es)")
    return 1 if mismatches else 0


if __name__ == "__main__":
    sys.exit(main())
