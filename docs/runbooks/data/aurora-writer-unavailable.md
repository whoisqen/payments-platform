# AuroraWriterUnavailable

Layer data, service aurora, severity critical, owner data-platform-oncall, failure mode `data-aurora-writer-unavailable`.
Dashboard: https://grafana.payments.internal/d/data-stores

## Symptom

postgres_exporter cannot reach the writer endpoint of a cell for 2 minutes.

## Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=AuroraWriterUnavailable`) runs the read-only step of SSM document `pay-runbook-aurora-writer-unavailable` and gathers metrics, events and sanitized logs.
2. Check the RDS event stream for a failover or maintenance event of the cluster.
3. Check the cluster writer instance and its AZ in the data-stores dashboard.
4. Check the drain lag and Redis stream length: they show how much write-behind is pending.

## Actions

1. If a failover is in progress, wait for it and watch the stream drain; no manual action while the writer is promoted.
2. If no failover started and the instance is unhealthy, start a failover with document step `failover-cluster`.
3. Keep the router running: payments continue in MemoryDB until the stream limit is reached.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-aurora-writer-unavailable`), which is audited.

## Escalation

Escalate to the commander when the stream length passes 50000 (alert RedisStreamBacklog) or the writer is down for more than 10 minutes. Default chain: primary acknowledges within 5 min, the secondary is paged at 5 min and the incident commander at 15 min (section 20.6).

## SSM document

`pay-runbook-aurora-writer-unavailable`
