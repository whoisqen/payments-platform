# Platform overhead latency SLO burn

Alerts `PaymentsPlatformOverheadLatencyBurnFast` (14.4x), `...BurnSlow` (6x) page; `...BurnTicket` (1x) opens a ticket.
SLO 99.9% of requests with a platform overhead (our time on top of the PSP time) under 150 ms; the budget is 43.2 minutes per 30 days. Dashboard: https://grafana.payments.internal/d/slo-overview

## Symptom

More than the allowed share of requests spend over 150 ms in the platform, not counting the PSP call.

## Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=PaymentsPlatformOverheadLatencyBurnFast`) runs the read-only step of SSM document `pay-runbook-platform-overhead-latency`.
2. Break the overhead into spans in Tempo (tail sampling keeps every request above 300 ms): locker call, MemoryDB, Aurora, routing.
3. Check retry rates (`retry-storm`), MemoryDB latency, locker latency and the cache warm ratio after a node replacement.

## Actions

1. If a dependency is slow, follow its runbook; the retry budget keeps retries below 10%.
2. If the HPA is at its maximum, raise `maxReplicas` through the chart values (step `scale-router`).
3. Roll back the last rollout if the latency started with it.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-platform-overhead-latency`), which is audited.

## Escalation

Primary acknowledges within 5 minutes, the secondary is paged at 5 minutes and the incident commander at 15 minutes (section 20.6). Payments-core lead joins when the slow path is in router code.

## SSM document

`pay-runbook-platform-overhead-latency`
