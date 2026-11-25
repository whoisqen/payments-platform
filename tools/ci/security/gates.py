#!/usr/bin/env python3
# Thresholds the scanner CLIs cannot read from a file: `get FILE KEY`, `semgrep-args FILE`, `sarif-gate FILE SARIF...` (exit 1 on a blocking level).
import argparse
import json
import sys
import tomllib
from pathlib import Path


def load(path):
    with open(path, "rb") as f:
        return tomllib.load(f)


def get(conf, key):
    value = conf[key]
    return [str(v) for v in value] if isinstance(value, list) else [str(value)]


def semgrep_args(conf):
    args = []
    for c in conf.get("configs", []):
        args += ["--config", c]
    for e in conf.get("exclude", []):
        args += ["--exclude", e]
    return args


def sarif_results(doc):
    for run in doc.get("runs", []):
        rules = {}
        driver = run.get("tool", {}).get("driver", {})
        for r in driver.get("rules", []) or []:
            rules[r.get("id")] = r.get("defaultConfiguration", {}).get("level")
        for res in run.get("results", []) or []:
            # a result without its own level inherits the rule default, then the SARIF default warning
            level = res.get("level") or rules.get(res.get("ruleId")) or "warning"
            loc = (res.get("locations") or [{}])[0].get("physicalLocation", {})
            path = loc.get("artifactLocation", {}).get("uri", "?")
            line = loc.get("region", {}).get("startLine", 0)
            yield res.get("ruleId", "?"), level, path, line


def sarif_gate(conf, files, out=sys.stdout):
    block = set(conf.get("block_levels", ["error"]))
    counts, blocking = {}, []
    for f in files:
        doc = json.loads(Path(f).read_text())
        for rule, level, path, line in sarif_results(doc):
            counts[level] = counts.get(level, 0) + 1
            if level in block:
                blocking.append(f"{path}:{line} {rule}")
    for b in blocking:
        print(f"::error::{b}", file=out)
    summary = ", ".join(f"{n} {lvl}" for lvl, n in sorted(counts.items())) or "no findings"
    print(f"sarif-gate: {summary}; blocking levels {sorted(block)}: {len(blocking)}", file=out)
    return 1 if blocking else 0


def main(argv=None):
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    g = sub.add_parser("get")
    g.add_argument("file")
    g.add_argument("key")
    s = sub.add_parser("semgrep-args")
    s.add_argument("file")
    sg = sub.add_parser("sarif-gate")
    sg.add_argument("file")
    sg.add_argument("sarif", nargs="+")
    a = p.parse_args(argv)
    conf = load(a.file)
    if a.cmd == "get":
        print("\n".join(get(conf, a.key)))
        return 0
    if a.cmd == "semgrep-args":
        print("\n".join(semgrep_args(conf)))
        return 0
    return sarif_gate(conf, a.sarif)


if __name__ == "__main__":
    sys.exit(main())
