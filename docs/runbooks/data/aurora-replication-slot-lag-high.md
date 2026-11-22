# AuroraReplicationSlotLagHigh

Layer data, service aurora, severity critical, owner data-platform-oncall, failure mode `data-aurora-replication-slot-lag-high`.
Dashboard: https://grafana.payments.internal/d/data-stores

## Symptom

A logical replication slot, usually the analytics change stream, is not consumed and retains WAL.

## Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=AuroraReplicationSlotLagHigh`) runs the read-only step of SSM document `pay-runbook-aurora-replication-slot-lag-high` and gathers metrics, events and sanitized logs.
2. Identify the slot and its consumer in `pg_replication_slots`.
3. Check the consumer (Kafka connector) health and its lag.

## Actions

1. Restart the stuck consumer.
2. If the consumer cannot catch up within 30 minutes, drop the slot with document step `drop-slot` and re-snapshot the analytics stream from the archive.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-aurora-replication-slot-lag-high`), which is audited.

## Escalation

Escalate to the commander if storage free space drops below 20% of the cluster volume. Default chain: primary acknowledges within 5 min, the secondary is paged at 5 min and the incident commander at 15 min (section 20.6).

## SSM document

`pay-runbook-aurora-replication-slot-lag-high`
