# MemoryDbMemoryCritical

Layer data, service memorydb, severity critical, owner data-platform-oncall, failure mode `data-memory-db-memory-critical`.
Dashboard: https://grafana.payments.internal/d/data-stores

## Symptom

MemoryDB memory use is above 85% of the node maximum.

## Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=MemoryDbMemoryCritical`) runs the read-only step of SSM document `pay-runbook-memory-db-memory-critical` and gathers metrics, events and sanitized logs.
2. Check the drainer: a stalled drainer keeps stream entries in memory.
3. Check the largest key groups and the stream length on the data-stores dashboard.

## Actions

1. If the drainer is behind, follow `drain-lag-high` first.
2. Scale the shard out with document step `scale-memorydb`; online resharding is supported.
3. Never flush keys to free memory: payment state lives there.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-memory-db-memory-critical`), which is audited.

## Escalation

Escalate to the commander when above 92%. Default chain: primary acknowledges within 5 min, the secondary is paged at 5 min and the incident commander at 15 min (section 20.6).

## SSM document

`pay-runbook-memory-db-memory-critical`
