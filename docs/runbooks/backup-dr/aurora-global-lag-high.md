# AuroraGlobalLagHigh

Layer backup-dr, service aurora, severity critical, owner data-platform-oncall, failure mode `backup-dr-aurora-global-lag-high`.
Dashboard: https://grafana.payments.internal/d/dr-switch

## Symptom

The replication lag to the headless secondary in us-east-1 exceeds 5 s (the metric is in milliseconds).

## Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=AuroraGlobalLagHigh`) runs the read-only step of SSM document `pay-runbook-aurora-global-lag-high` and gathers metrics, events and sanitized logs.
2. Check the write rate of the cluster and the cross-region network.
3. Check the lag per secondary region to see whether one link is slow.

## Actions

1. Reduce heavy batch writes (migrations, backfills) with document step `pause-batch`.
2. Do not enable `rds.global_db_rpo`: it pauses commits in Frankfurt.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-aurora-global-lag-high`), which is audited.

## Escalation

Escalate when the lag passes 10 s: see `aurora-global-lag-rpo-budget-exceeded`. Default chain: primary acknowledges within 5 min, the secondary is paged at 5 min and the incident commander at 15 min (section 20.6).

## SSM document

`pay-runbook-aurora-global-lag-high`
