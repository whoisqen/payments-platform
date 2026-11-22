#!/usr/bin/env python3
"""Compute alert coverage per layer from the failure-mode catalog (architecture section 25.3)."""
import argparse
import json
import re
import sys
from pathlib import Path

import yaml

HERE = Path(__file__).resolve().parent
OBS = HERE.parent
REPO = OBS.parent
REQUIRED_LABELS = ("severity", "team", "service", "owner")
REQUIRED_ANNOTATIONS = ("summary", "runbook_url", "dashboard_url")
KEYWORDS = {"and", "or", "unless", "bool", "offset", "inf", "nan", "start", "end"}
DIAGNOSTICS_HEADING = re.compile(r"^#{2,3} (Diagnostics|Diagnostic)\b|^\*\*Diagnostics", re.M)


def extract_metrics(expr):
    s = re.sub(r'"(?:\\.|[^"\\])*"', '""', expr)
    s = re.sub(r"\{[^}]*\}", "", s)
    s = re.sub(r"\[[^\]]*\]", "", s)
    s = re.sub(r"\b(by|without|on|ignoring)\s*\([^)]*\)", " ", s)
    s = re.sub(r"\b(group_left|group_right)\s*(\([^)]*\))?", " ", s)
    found = set()
    for m in re.finditer(r"(?<![A-Za-z0-9_:.])[A-Za-z_:][A-Za-z0-9_:]*", s):
        tok = m.group(0)
        if tok in KEYWORDS or re.match(r"\s*\(", s[m.end():]):
            continue
        found.add(tok)
    return found


def load_rules(roots):
    alerts, recorded = {}, set()
    for root in roots:
        for path in sorted(Path(root).rglob("*.yaml")):
            doc = yaml.safe_load(path.read_text())
            for group in doc["spec"]["groups"]:
                for rule in group["rules"]:
                    if "record" in rule:
                        recorded.add(rule["record"])
                    else:
                        alerts[rule["alert"]] = {**rule, "file": str(path)}
    return alerts, recorded


def load_catalog(catalog_dir):
    modes = []
    for path in sorted(Path(catalog_dir).glob("*.yaml")):
        modes.extend(yaml.safe_load(path.read_text())["modes"])
    return modes


def runbook_path(url, repo=REPO):
    marker = "/docs/runbooks/"
    if marker not in url:
        return None
    return repo / "docs" / "runbooks" / url.split(marker, 1)[1].split("#", 1)[0]


def check_mode(mode, alerts, recorded, metrics, repo=REPO):
    name = mode.get("alert")
    if not name:
        return "no alert defined"
    rule = alerts.get(name)
    if rule is None:
        return f"alert {name} not found in rules"
    labels, ann = rule.get("labels", {}), rule.get("annotations", {})
    missing = [k for k in REQUIRED_LABELS if k not in labels] + [k for k in REQUIRED_ANNOTATIONS if k not in ann]
    if missing:
        return "alert lacks " + ", ".join(missing)
    path = runbook_path(ann["runbook_url"], repo)
    if path is None or not path.is_file():
        return "runbook file does not exist"
    if not DIAGNOSTICS_HEADING.search(path.read_text()):
        return "runbook has no diagnostics"
    absent = sorted(m for m in extract_metrics(rule["expr"]) if m not in metrics and m not in recorded)
    if absent:
        return "metric not exported: " + ", ".join(absent)
    return None


def compute(modes, alerts, recorded, metrics, targets, repo=REPO):
    layers = {}
    for mode in modes:
        layer = layers.setdefault(mode["layer"], {"total": 0, "covered": 0, "uncovered": []})
        layer["total"] += 1
        problem = check_mode(mode, alerts, recorded, metrics, repo)
        if problem:
            layer["uncovered"].append({"id": mode["id"], "reason": problem})
        else:
            layer["covered"] += 1
    for name, layer in layers.items():
        layer["ratio"] = round(layer["covered"] / layer["total"], 4)
        layer["target"] = targets.get(name, targets.get("default", 0.8))
        layer["meets_target"] = layer["ratio"] >= layer["target"]
    return layers


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out", default=str(HERE / "report.json"))
    ap.add_argument("--fail-below-target", action="store_true")
    args = ap.parse_args(argv)
    alerts, recorded = load_rules([OBS / "alerts", OBS / "slo" / "generated"])
    modes = load_catalog(HERE / "catalog")
    metrics = set(json.loads((HERE / "metrics-catalog.json").read_text())["metrics"])
    targets = yaml.safe_load((HERE / "targets.yaml").read_text())["targets"]
    layers = compute(modes, alerts, recorded, metrics, targets)
    known = {m["id"] for m in modes}
    unknown_alerts = sorted(n for n, r in alerts.items() if r.get("labels", {}).get("failure_mode") not in known)
    report = {"layers": layers, "alerts_without_failure_mode": unknown_alerts}
    Path(args.out).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    for name, layer in sorted(layers.items()):
        flag = "ok" if layer["meets_target"] else "BELOW TARGET"
        print(f"{name:14} {layer['covered']:3}/{layer['total']:3} {layer['ratio']:.0%} (target {layer['target']:.0%}) {flag}")
    return 1 if args.fail_below_target and not all(v["meets_target"] for v in layers.values()) else 0


if __name__ == "__main__":
    sys.exit(main())
