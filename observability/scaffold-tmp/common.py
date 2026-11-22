import json
import re
import sys
from pathlib import Path

import yaml

REPO = Path("/data/vlad/portfolio/payments-platform/.claude/worktrees/agent-a1894cfe0c95fc100")

RB_URL = "https://github.com/whoisqen/payments-platform/blob/main/docs/runbooks"
GRAFANA = "https://grafana.payments.internal/d"
PAGING = ("critical", "security")
ALL = []
GAPS = []
EXTRA_MODES = []


def kebab(name):
    return re.sub(r"(?<=[a-z0-9])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])", "-", name).lower()


def a(**kw):
    kw.setdefault("f", "5m")
    kw.setdefault("labels", None)
    kw.setdefault("spike", None)
    kw.setdefault("T", None)
    kw.setdefault("extra_tests", [])
    kw.setdefault("skip_auto", False)
    kw.setdefault("norules", False)
    kw.setdefault("eval_interval", "1m")
    ALL.append(kw)


def gap(layer, id, component, failure, impact, severity, reason):
    GAPS.append(dict(layer=layer, id=f"{layer}-{id}", component=component, failure=failure, impact=impact, severity=severity, alert=None, signal="metric", reason=reason))


def minutes(f):
    m = re.fullmatch(r"(\d+)([smh])", f)
    return {"m": 1, "h": 60, "s": 0}[m.group(2)] * int(m.group(1))


def rb_url(al):
    k = kebab(al["name"])
    if al["sev"] in PAGING:
        return f"{RB_URL}/{al['layer']}/{k}.md"
    return f"{RB_URL}/{al['layer']}/warnings.md#{k}"


def rule_labels(al):
    return {"severity": al["sev"], "team": al["team"], "service": al["svc"], "owner": f"{al['team']}-oncall", "layer": al["layer"], "failure_mode": al.get("fm") or f"{al['layer']}-{kebab(al['name'])}"}


def annotations(al):
    return {"summary": al["sum"], "runbook_url": rb_url(al), "dashboard_url": f"{GRAFANA}/{al['dash']}"}


def dump(obj):
    return yaml.safe_dump(obj, sort_keys=False, width=10000)


def render_rules(layer, group, items):
    rules = []
    for al in items:
        r = {"alert": al["name"], "expr": al["expr"]}
        if al["f"] not in ("0m", "0s"):
            r["for"] = al["f"]
        r["labels"] = rule_labels(al)
        r["annotations"] = annotations(al)
        rules.append(r)
    doc = {
        "apiVersion": "monitoring.coreos.com/v1",
        "kind": "PrometheusRule",
        "metadata": {"name": f"alerts-{layer}-{group}", "namespace": "monitoring", "labels": {"app.kubernetes.io/part-of": "payments-platform", "prometheus": "platform"}},
        "spec": {"groups": [{"name": f"{layer}-{group}", "rules": rules}]},
    }
    return dump(doc)


def sel_labels(sel):
    m = re.search(r"\{(.*)\}", sel)
    out = {}
    if m:
        for k, v in re.findall(r'(\w+)="([^"]*)"', m.group(1)):
            out[k] = v
    return out


def expected(al):
    lab = al["labels"]
    if lab is None:
        lab = sel_labels(al["series"][0][0])
    return {**rule_labels(al), **lab}


def series_block(al, mode, n):
    out = []
    for sel, bad, good in al["series"]:
        if mode == "bad":
            v = bad.format(n=n)
        elif mode == "good":
            v = good.format(n=n)
        else:
            v = f"{good.format(n=9)} {bad.format(n=1)} {good.format(n=n - 12)}"
        out.append({"series": sel, "values": v})
    return out


def is_gauge(al):
    return all("+" not in s[1] and "+" not in s[2] for s in al["series"])


def render_tests(layer, group, items, rule_path):
    tests = []
    for al in items:
        if al["skip_auto"]:
            tests.extend(al["extra_tests"])
            continue
        T = al["T"] or max(15, minutes(al["f"]) + 12)
        n = T + 4
        name = al["name"]
        fire = {"eval_time": f"{T}m", "alertname": name, "exp_alerts": [{"exp_labels": expected(al), "exp_annotations": annotations(al)}]}
        quiet = {"eval_time": f"{T}m", "alertname": name, "exp_alerts": []}
        tests.append({"interval": "1m", "input_series": series_block(al, "bad", n), "alert_rule_test": [fire]})
        tests.append({"interval": "1m", "input_series": series_block(al, "good", n), "alert_rule_test": [quiet]})
        spike = al["spike"] if al["spike"] is not None else (is_gauge(al) and minutes(al["f"]) >= 5)
        if spike:
            tests.append({"interval": "1m", "input_series": series_block(al, "spike", n), "alert_rule_test": [quiet]})
        tests.extend(al["extra_tests"])
    doc = {"rule_files": [rule_path], "evaluation_interval": items[0]["eval_interval"], "tests": tests}
    return dump(doc)


def detect(al):
    return f"{minutes(al['f']) + 3}m"


def runbook_paging(al):
    k = kebab(al["name"])
    esc = "primary acknowledges within 5 min, the secondary is paged at 5 min and the incident commander at 15 min (section 20.6)"
    if al["sev"] == "security":
        esc = "the security on-call acknowledges within 5 min and opens an incident; the incident commander joins at 15 min; PCI-relevant findings are reported to the compliance owner the same day"
    diag = "\n".join(f"{i}. {d}" for i, d in enumerate(al["diag"], 2))
    act = "\n".join(f"{i}. {d}" for i, d in enumerate(al["act"], 1))
    return f"""# {al['name']}

Layer {al['layer']}, service {al['svc']}, severity {al['sev']}, owner {al['team']}-oncall, failure mode `{rule_labels(al)['failure_mode']}`.
Dashboard: {GRAFANA}/{al['dash']}

## Symptom

{al['sym']}

## Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert={al['name']}`) runs the read-only step of SSM document `pay-runbook-{k}` and gathers metrics, events and sanitized logs.
{diag}

## Actions

{act}

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-{k}`), which is audited.

## Escalation

{al['esc']} Default chain: {esc}.

## SSM document

`pay-runbook-{k}`
"""


def runbook_warnings(layer, items):
    out = [f"# {layer}: non-paging alerts\n\nEach section is the runbook of one ticket or Slack alert; the alert annotation links to its anchor. A ticket is handled in working hours; if the condition persists past the stated escalation, the owner raises it to the on-call.\n"]
    for al in items:
        k = kebab(al["name"])
        diag = "\n".join(f"{i}. {d}" for i, d in enumerate(al["diag"], 2))
        act = "\n".join(f"{i}. {d}" for i, d in enumerate(al["act"], 1))
        out.append(f"""## {k}

Alert `{al['name']}`, severity {al['sev']}, owner {al['team']}-oncall, dashboard {GRAFANA}/{al['dash']}.

### Symptom

{al['sym']}

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert={al['name']}`) runs the read-only step of SSM document `pay-runbook-{k}`.
{diag}

### Actions

{act}

### Escalation

{al['esc']}

### SSM document

`pay-runbook-{k}`
""")
    return "\n".join(out)


def mode_of(al):
    return dict(layer=al["layer"], id=rule_labels(al)["failure_mode"], component=al["comp"], failure=al["failure"], impact=al["impact"], severity=al["sev"], alert=al["name"], signal="metric", detect_within=detect(al))


def write(path, text):
    p = REPO / path
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text)


def emit():
    by = {}
    for al in ALL:
        by.setdefault((al["layer"], al["group"]), []).append(al)
    for (layer, group), items in by.items():
        if not all(al["norules"] for al in items):
            write(f"observability/alerts/{layer}/{group}.yaml", render_rules(layer, group, items))
        write(f"observability/tests/{layer}/{group}.test.yaml", render_tests(layer, group, items, f"../../alerts/{layer}/{group}.yaml"))
    layers = sorted({al["layer"] for al in ALL})
    order = {"network": "01", "compute": "02", "data": "03", "application": "05", "security-pci": "06", "backup-dr": "08", "meta": "09"}
    for layer in layers:
        pag = [al for al in ALL if al["layer"] == layer and al["sev"] in PAGING]
        non = [al for al in ALL if al["layer"] == layer and al["sev"] not in PAGING]
        for al in pag:
            write(f"docs/runbooks/{layer}/{kebab(al['name'])}.md", runbook_paging(al))
        if non:
            write(f"docs/runbooks/{layer}/warnings.md", runbook_warnings(layer, non))
        modes = [mode_of(al) for al in ALL if al["layer"] == layer] + [dict(m) for m in EXTRA_MODES if m["layer"] == layer] + [dict(g) for g in GAPS if g["layer"] == layer]
        write(f"observability/coverage/catalog/{order[layer]}-{layer}.yaml", "# Single place where failure modes are added; a mode without alert stays a visible gap.\n" + dump({"modes": modes}))
