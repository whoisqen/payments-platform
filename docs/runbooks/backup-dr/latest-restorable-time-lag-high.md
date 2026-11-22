# LatestRestorableTimeLagHigh

Layer backup-dr, service aurora, severity critical, owner data-platform-oncall, failure mode `backup-dr-latest-restorable-time-lag-high`.
Dashboard: https://grafana.payments.internal/d/backup

## Symptom

The latest restorable time of an Aurora cluster or a DynamoDB table is more than 5 minutes behind now for 10 minutes.

## Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=LatestRestorableTimeLagHigh`) runs the read-only step of SSM document `pay-runbook-latest-restorable-time-lag-high` and gathers metrics, events and sanitized logs.
2. Check the cluster events and the continuous backup status of the resource.
3. Check whether a writer failover or maintenance interrupted the log shipping.

## Actions

1. If continuous backup is off, restore the setting through Terraform.
2. Open an AWS support case if the status is healthy but the lag stays.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-latest-restorable-time-lag-high`), which is audited.

## Escalation

Escalate to the commander when the lag exceeds 30 minutes. Default chain: primary acknowledges within 5 min, the secondary is paged at 5 min and the incident commander at 15 min (section 20.6).

## SSM document

`pay-runbook-latest-restorable-time-lag-high`
