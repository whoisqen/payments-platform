#!/usr/bin/env python3
# Resolves a runbook-diagnose or runbook-actions request against docs/runbooks: only documented alerts, documents and steps reach SSM.
import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
ENVS = ("dev", "stage", "prod")
REGIONS = ("eu-central-1", "us-east-1", "us-east-2")
DIAG = re.compile(r"input `alert=([A-Za-z0-9]+)`\) runs the read-only step of SSM document `(pay-runbook-[a-z0-9-]+)`")
DOC = re.compile(r"`(pay-runbook-[a-z0-9-]+)`")
STEP = re.compile(r"document step `([a-z0-9-]+)`")
SECTION = re.compile(r"^## (?!Symptom|Diagnostics|Actions|Escalation|SSM document)", re.M)


class RunbookError(Exception):
    pass


def sections(root):
    for path in sorted((Path(root) / "docs/runbooks").rglob("*.md")):
        text = path.read_text(encoding="utf-8")
        starts = [m.start() for m in SECTION.finditer(text)] or [0]
        bounds = ([0] if starts[0] else []) + starts + [len(text)]
        for a, b in zip(bounds, bounds[1:], strict=False):
            yield path.relative_to(root).as_posix(), text[a:b]


def catalog(root=ROOT):
    alerts, documents = {}, {}
    for path, text in sections(root):
        for alert, doc in DIAG.findall(text):
            alerts[alert] = doc
        docs = set(DOC.findall(text))
        if len(docs) == 1:
            doc = docs.pop()
            entry = documents.setdefault(doc, {"runbook": path, "steps": set()})
            entry["steps"] |= set(STEP.findall(text))
    return alerts, documents


def roles(cfg, env, kind):
    account, prefix = str(cfg["accounts"][env]), cfg["naming"]["prefix"]
    base = f"arn:aws:iam::{account}:role/{prefix}-{env}-glob-runbook-{kind}"
    return {"role": base, "execution_role": f"{base}-exec"}


def check_target(env, region):
    if env not in ENVS:
        raise RunbookError(f"environment must be one of {', '.join(ENVS)}")
    if region not in REGIONS:
        raise RunbookError(f"region must be one of {', '.join(REGIONS)}")


def diagnose(cat, cfg, alert, env, region):
    check_target(env, region)
    doc = cat[0].get(alert or "")
    if not doc:
        raise RunbookError(f"no runbook documents the alert {alert!r}")
    return {"document": doc, "region": region, "mode": "diagnose", "step": "", **roles(cfg, env, "diagnose")}


def action(cat, cfg, document, step, env, region):
    check_target(env, region)
    entry = cat[1].get(document or "")
    if not entry:
        raise RunbookError(f"no runbook names the SSM document {document!r}")
    steps = sorted(entry["steps"])
    if steps and step not in steps:
        raise RunbookError(f"{document} ({entry['runbook']}) has the steps {', '.join(steps)}; pass one of them")
    if not steps and step:
        raise RunbookError(f"{document} ({entry['runbook']}) names no step; leave step empty")
    return {"document": document, "region": region, "mode": "act", "step": step, **roles(cfg, env, "actions")}


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("kind", choices=["diagnose", "action"])
    ap.add_argument("--alert", default="")
    ap.add_argument("--document", default="")
    ap.add_argument("--step", default="")
    ap.add_argument("--env", required=True)
    ap.add_argument("--region", default="eu-central-1")
    ns = ap.parse_args(argv)
    try:
        import yaml

        cfg = yaml.safe_load((ROOT / "config/platform.yaml").read_text(encoding="utf-8"))
        cat = catalog()
        out = diagnose(cat, cfg, ns.alert, ns.env, ns.region) if ns.kind == "diagnose" else \
            action(cat, cfg, ns.document, ns.step, ns.env, ns.region)
        print(json.dumps(out))
    except RunbookError as e:
        print(f"runbook: error: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
