#!/usr/bin/env python3
"""Check of the BuildKit pin in tools/ci/buildkit/buildkit.env.

  buildkit_pin_check.py           unresolved digest is a warning, exit code 0
  buildkit_pin_check.py --strict  unresolved digest is an error, exit code 1 (the images workflow uses it)

A malformed pin (no rootless tag, latest, a digest that is neither sha256 nor the placeholder) is always an error.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PIN = ROOT / "tools/ci/buildkit/buildkit.env"
IMAGE = re.compile(r"^(?P<repo>[a-z0-9./_-]+):(?P<tag>[A-Za-z0-9._-]+)@(?P<digest>.+)$")
DIGEST = re.compile(r"^sha256:[a-f0-9]{64}$")
PLACEHOLDER = re.compile(r"^sha256:REPLACE_\w+$")


def check(text):
    """Return (errors, unresolved) for the content of the env file."""
    values = dict(
        line.split("=", 1) for line in text.splitlines() if "=" in line and not line.lstrip().startswith("#")
    )
    ref = values.get("BUILDKIT_IMAGE", "").strip()
    if not ref:
        return ["BUILDKIT_IMAGE is not set"], []
    m = IMAGE.match(ref)
    if not m:
        return [f"BUILDKIT_IMAGE {ref!r} is not <repository>:<tag>@sha256:<digest>"], []
    errors, unresolved = [], []
    if not m["tag"].endswith("-rootless"):
        errors.append(f"tag {m['tag']} is not a -rootless image")
    if m["tag"].startswith("latest"):
        errors.append("tag is latest")
    if PLACEHOLDER.match(m["digest"]):
        unresolved.append(m["digest"])
    elif not DIGEST.match(m["digest"]):
        errors.append(f"digest {m['digest']!r} is not sha256:<64 hex>")
    return errors, unresolved


def main(argv=None):
    args = list(sys.argv[1:] if argv is None else argv)
    strict = "--strict" in args
    path = Path(next((a for a in args if not a.startswith("--")), PIN))
    errors, unresolved = check(path.read_text(encoding="utf-8"))
    for e in errors:
        print(f"::error file={path.name}::{e}")
    for u in unresolved:
        level = "error" if strict else "warning"
        print(f"::{level} file={path.name}::unresolved BuildKit digest {u} (Renovate fills it; owner supplies it until then)")
    print(f"buildkit pin: {len(errors)} error(s), {len(unresolved)} unresolved ({'blocking' if strict else 'warning only'})")
    return 1 if errors or (strict and unresolved) else 0


if __name__ == "__main__":
    sys.exit(main())
