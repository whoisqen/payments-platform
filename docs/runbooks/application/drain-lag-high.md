# DrainLagHigh

Layer application, service drainer, severity critical, owner payments-core-oncall, failure mode `application-drain-lag-high`.
Dashboard: https://grafana.payments.internal/d/drainer

## Symptom

The time from the Redis stream write to the row in PostgreSQL is above 5 seconds.

## Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=DrainLagHigh`) runs the read-only step of SSM document `pay-runbook-drain-lag-high` and gathers metrics, events and sanitized logs.
2. Check the drainer pods and the batch size on the drainer dashboard.
3. Check Aurora writer CPU, locks and `AuroraWriterUnavailable`.
4. Check the stream length: `redis-stream-backlog`.

## Actions

1. Scale the drainer consumers with document step `scale-drainer`.
2. If the writer is the bottleneck, follow the Aurora runbooks.
3. Never trim the stream: it holds undrained payment state.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-drain-lag-high`), which is audited.

## Escalation

Escalate to the commander when the lag exceeds 60 seconds. Default chain: primary acknowledges within 5 min, the secondary is paged at 5 min and the incident commander at 15 min (section 20.6).

## SSM document

`pay-runbook-drain-lag-high`
