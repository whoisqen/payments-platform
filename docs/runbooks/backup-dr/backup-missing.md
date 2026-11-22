# BackupMissing

Layer backup-dr, service aws-backup, severity critical, owner data-platform-oncall, failure mode `backup-dr-backup-missing`.
Dashboard: https://grafana.payments.internal/d/backup

## Symptom

No successful backup of the store within two intervals.

## Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=BackupMissing`) runs the read-only step of SSM document `pay-runbook-backup-missing` and gathers metrics, events and sanitized logs.
2. Check the backup plan schedule and the last job of the resource.

## Actions

1. Run an on-demand backup with `start-backup`; check that the plan still selects the resource by tag.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-backup-missing`), which is audited.

## Escalation

Escalate to the commander for payment databases. Default chain: primary acknowledges within 5 min, the secondary is paged at 5 min and the incident commander at 15 min (section 20.6).

## SSM document

`pay-runbook-backup-missing`
