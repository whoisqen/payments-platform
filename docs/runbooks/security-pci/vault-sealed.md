# VaultSealed

Layer security-pci, service vault, severity critical, owner security-oncall, failure mode `security-pci-vault-sealed`.
Dashboard: https://grafana.payments.internal/d/edge

## Symptom

Vault reports it is sealed.

## Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=VaultSealed`) runs the read-only step of SSM document `pay-runbook-vault-sealed` and gathers metrics, events and sanitized logs.
2. Check the Vault pod logs for the cause: restart, node loss, auto-unseal KMS error.
3. Check the KMS key policy used for auto-unseal.

## Actions

1. Auto-unseal normally recovers it; if KMS access failed, restore the key grant through Terraform.
2. If a node restore is needed, use the latest Raft snapshot (hourly) with document step `restore-vault`.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-vault-sealed`), which is audited.

## Escalation

Escalate to the commander if it stays sealed for 10 minutes. Default chain: primary acknowledges within 5 min, the secondary is paged at 5 min and the incident commander at 15 min (section 20.6).

## SSM document

`pay-runbook-vault-sealed`
