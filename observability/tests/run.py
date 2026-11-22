#!/usr/bin/env python3
"""Run promtool check and test over the PrometheusRule files; promtool reads plain groups, so the spec is unwrapped into a mirror tree."""
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

OBS = Path(__file__).resolve().parents[1]
RULE_DIRS = ["alerts", "slo/generated"]


def unwrap(mirror):
    files = []
    for rel in RULE_DIRS:
        for src in sorted((OBS / rel).rglob("*.yaml")):
            doc = yaml.safe_load(src.read_text())
            target = mirror / src.relative_to(OBS)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(yaml.safe_dump(doc["spec"], sort_keys=False, width=10000))
            files.append(target)
    return files


def run(cmd):
    res = subprocess.run(cmd, capture_output=True, text=True)
    out = (res.stdout + res.stderr).strip()
    return res.returncode, out


def main():
    promtool = shutil.which("promtool")
    if not promtool:
        print("run: promtool not found", file=sys.stderr)
        return 2
    failed = 0
    with tempfile.TemporaryDirectory() as tmp:
        mirror = Path(tmp)
        rule_files = unwrap(mirror)
        code, out = run([promtool, "check", "rules", *map(str, rule_files)])
        print(f"check rules: {len(rule_files)} files, exit {code}")
        if code:
            print(out)
            failed += 1
        tests = sorted((OBS / "tests").rglob("*.test.yaml"))
        for test in tests:
            target = mirror / test.relative_to(OBS)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(test, target)
        for test in tests:
            code, out = run([promtool, "test", "rules", str(mirror / test.relative_to(OBS))])
            if code:
                failed += 1
                print(f"FAIL {test.relative_to(OBS)}\n{out}")
        print(f"test rules: {len(tests)} files, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
