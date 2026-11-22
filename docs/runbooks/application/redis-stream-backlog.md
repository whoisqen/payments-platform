# RedisStreamBacklog

Layer application, service drainer, severity critical, owner payments-core-oncall, failure mode `application-redis-stream-backlog`.
Dashboard: https://grafana.payments.internal/d/drainer

## Symptom

The stream that feeds the drainer is longer than 50000 entries.

## Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=RedisStreamBacklog`) runs the read-only step of SSM document `pay-runbook-redis-stream-backlog` and gathers metrics, events and sanitized logs.
2. Check `drain-lag-high` and the drainer pods.
3. Check MemoryDB memory: `memory-db-memory-critical`.

## Actions

1. Follow `drain-lag-high` to restore the drain rate.
2. Scale MemoryDB out if memory passes 85%.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-redis-stream-backlog`), which is audited.

## Escalation

Escalate to the commander if memory passes 85%. Default chain: primary acknowledges within 5 min, the secondary is paged at 5 min and the incident commander at 15 min (section 20.6).

## SSM document

`pay-runbook-redis-stream-backlog`
