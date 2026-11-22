# GuardDutyRuntimeCdeFinding

Layer security-pci, service guardduty, severity security, owner security-oncall, failure mode `security-pci-guard-duty-runtime-cde-finding`.
Dashboard: https://grafana.payments.internal/d/edge

## Symptom

Runtime Monitoring detected suspicious behaviour in a CDE cluster.

## Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=GuardDutyRuntimeCdeFinding`) runs the read-only step of SSM document `pay-runbook-guard-duty-runtime-cde-finding` and gathers metrics, events and sanitized logs.
2. Read the finding: container, process, network connection.
3. Check Kyverno audit results and recent deploys of that workload.

## Actions

1. Cordon the node and scale the workload to zero with document step `quarantine-workload`; keep the node for forensics.
2. Do not copy data out of the CDE; forensic tooling runs inside it.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-guard-duty-runtime-cde-finding`), which is audited.

## Escalation

Open a security incident; the compliance owner is informed the same day. Default chain: the security on-call acknowledges within 5 min and opens an incident; the incident commander joins at 15 min; PCI-relevant findings are reported to the compliance owner the same day.

## SSM document

`pay-runbook-guard-duty-runtime-cde-finding`
