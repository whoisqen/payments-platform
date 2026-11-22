# PanDetectedInLogs

Layer security-pci, service otel-collector, severity security, owner security-oncall, failure mode `security-pci-pan-detected-in-logs`.
Dashboard: https://grafana.payments.internal/d/edge

## Symptom

The redaction processor or Macie found a PAN pattern in logs, traces or metrics.

## Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=PanDetectedInLogs`) runs the read-only step of SSM document `pay-runbook-pan-detected-in-logs` and gathers metrics, events and sanitized logs.
2. Find the emitting service and field from the collector attribute counters (never from the value).
3. Check the last deploy of that service for a new log statement.

## Actions

1. Roll back or patch the emitting code; keep the masking rule on.
2. Purge the affected log streams in Loki and the S3 archive with the security document step `purge-logs` (needs two approvals).

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-pan-detected-in-logs`), which is audited.

## Escalation

Open a security incident and a PCI-impact note; never paste the matched value into a ticket. Default chain: the security on-call acknowledges within 5 min and opens an incident; the incident commander joins at 15 min; PCI-relevant findings are reported to the compliance owner the same day.

## SSM document

`pay-runbook-pan-detected-in-logs`
