#!/usr/bin/env python3
# Sections 11 (PostToolUse) and 18: format, lint and test by file type. A missing tool is skipped.
import shutil, subprocess, sys
from pathlib import Path
import _common
from _common import payload, block, init_root

_p = payload()
path = (_p.get("tool_input") or {}).get("file_path")
init_root(_p, path if isinstance(path, str) else None)
ROOT = _common.ROOT

r = _common.rel(path) if path else None
if not r or not (ROOT / r).is_file():
    raise SystemExit(0)


def run(cmd, cwd=ROOT):
    if shutil.which(cmd[0]) is None:
        return
    p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=280)
    if p.returncode:
        block(f"{' '.join(cmd)} exited with code {p.returncode}:\n{p.stdout}{p.stderr}")


f = ROOT / r
# Upstream code is not ours to lint; the crates rust-engineer may patch are checked.
if r.startswith("vendor/") and not r.startswith(("vendor/hyperswitch/crates/", "vendor/card-vault/")):
    raise SystemExit(0)
if f.suffix == ".rs":
    crate = next((d for d in f.parents if (d / "Cargo.toml").exists()), None)
    if crate:
        run(["cargo", "fmt"], crate)
        run(["cargo", "clippy", "--", "-D", "warnings"], crate)
elif f.suffix == ".tf":
    run(["terraform", "fmt", str(f)])
    run(["tflint", "--chdir", str(f.parent)])
elif r.startswith("deploy/") and f.suffix in (".yaml", ".yml") and "/templates/" not in r and not f.name.startswith("values"):
    run(["kubeconform", "-ignore-missing-schemas", str(f)])
elif r.startswith("policy/"):
    if f.suffix == ".rego":
        run(["opa", "test", str(f.parent)])
    elif r.startswith("policy/kyverno/"):
        run(["kyverno", "test", str(f.parent)])
lint = ROOT / "tools" / "lint" / "comments"
if lint.exists():
    run([str(lint), str(f)])
