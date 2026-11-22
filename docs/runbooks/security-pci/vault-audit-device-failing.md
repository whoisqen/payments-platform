# VaultAuditDeviceFailing

Layer security-pci, service vault, severity critical, owner security-oncall, failure mode `security-pci-vault-audit-device-failing`.
Dashboard: https://grafana.payments.internal/d/edge

## Symptom

Writes to the Vault audit device fail.

## Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=VaultAuditDeviceFailing`) runs the read-only step of SSM document `pay-runbook-vault-audit-device-failing` and gathers metrics, events and sanitized logs.
2. Check the audit device target (S3 or socket) and its credentials.
3. Check the disk of the audit sink.

## Actions

1. Fix the audit sink; do not disable the audit device.
2. Enable a second audit device through the Vault-as-code PR to avoid a single point of failure.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-vault-audit-device-failing`), which is audited.

## Escalation

Escalate to the commander if secret reads start failing. Default chain: primary acknowledges within 5 min, the secondary is paged at 5 min and the incident commander at 15 min (section 20.6).

## SSM document

`pay-runbook-vault-audit-device-failing`
