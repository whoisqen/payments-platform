#!/usr/bin/env python3
"""Prints the cargo package arguments for the crates a diff touched in one vendored workspace.

  rust_scope.py --workspace vendor/hyperswitch --base SHA --head SHA
  rust_scope.py --workspace vendor/hyperswitch --all

Output is one line: `--workspace`, `-p a -p b`, or empty when no crate of the workspace changed.
"""
import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
# a change here can affect every crate of the workspace
WORKSPACE_FILES = ("Cargo.toml", "Cargo.lock", "rust-toolchain", "rust-toolchain.toml", ".cargo/", "build.rs")
NAME = re.compile(r'^\s*name\s*=\s*"([A-Za-z0-9_-]+)"', re.M)


def crate_name(manifest_text):
    package = manifest_text.split("[package]", 1)
    if len(package) != 2:
        return None
    body = package[1].split("\n[", 1)[0]
    m = NAME.search(body)
    return m.group(1) if m else None


def scope(files, workspace, read_manifest):
    prefix = workspace.rstrip("/") + "/"
    crates = set()
    for f in files:
        if not f.startswith(prefix):
            continue
        rel = f[len(prefix):]
        if rel.endswith(".md"):
            continue
        if rel.startswith(WORKSPACE_FILES) or rel in WORKSPACE_FILES:
            return ["--workspace"]
        parts = rel.split("/")
        if parts[0] == "crates" and len(parts) > 2:
            name = crate_name(read_manifest(f"{prefix}crates/{parts[1]}/Cargo.toml") or "")
            if name is None:
                return ["--workspace"]
            crates.add(name)
        elif parts[0] == "src" or parts[0] == "benches" or parts[0] == "tests":
            # a single-crate workspace such as card-vault
            return ["--workspace"]
    out = []
    for c in sorted(crates):
        out += ["-p", c]
    return out


def changed_files(base, head):
    r = subprocess.run(["git", "diff", "--name-only", f"{base}...{head}"], cwd=ROOT, capture_output=True, text=True)
    if r.returncode != 0:
        return None
    return [x for x in r.stdout.splitlines() if x]


def read_manifest(rel):
    p = ROOT / rel
    return p.read_text(encoding="utf-8") if p.is_file() else None


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--workspace", required=True)
    ap.add_argument("--base")
    ap.add_argument("--head")
    ap.add_argument("--all", action="store_true")
    ns = ap.parse_args(argv)
    if ns.all or not (ns.base and ns.head):
        print("--workspace")
        return 0
    files = changed_files(ns.base, ns.head)
    # an unknown diff tests everything: a slow run is cheaper than a skipped crate
    print(" ".join(["--workspace"] if files is None else scope(files, ns.workspace, read_manifest)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
