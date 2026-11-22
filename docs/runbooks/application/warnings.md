# application: non-paging alerts

Each section is the runbook of one ticket or Slack alert; the alert annotation links to its anchor. A ticket is handled in working hours; if the condition persists past the stated escalation, the owner raises it to the on-call.

## psp-latency-p99-high

Alert `PspLatencyP99High`, severity warning, owner payments-core-oncall, dashboard https://grafana.payments.internal/d/payments.

### Symptom

The p99 of the PSP call duration is above 3 seconds.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=PspLatencyP99High`) runs the read-only step of SSM document `pay-runbook-psp-latency-p99-high`.
2. Compare with the PSP profile timeout and the share of timeouts.

### Actions

1. Lower the routing weight of the PSP if the share of timeouts grows.

### Escalation

Ticket to payments-core; the PSP degraded alert pages if errors follow.

### SSM document

`pay-runbook-psp-latency-p99-high`

## psp-circuit-breaker-open

Alert `PspCircuitBreakerOpen`, severity warning, owner payments-core-oncall, dashboard https://grafana.payments.internal/d/payments.

### Symptom

The router opened the breaker of a PSP (state 2).

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=PspCircuitBreakerOpen`) runs the read-only step of SSM document `pay-runbook-psp-circuit-breaker-open`.
2. Read the breaker trip reason and the half-open probe results on the router dashboard.

### Actions

1. No manual action if the half-open probe recovers; otherwise follow `psp-degraded`.

### Escalation

Ticket to payments-core.

### SSM document

`pay-runbook-psp-circuit-breaker-open`

## authorization-rate-drop

Alert `AuthorizationRateDrop`, severity warning, owner payments-core-oncall, dashboard https://grafana.payments.internal/d/payments.

### Symptom

The authorization rate of a PSP is at least 5 percentage points below the same hour one week ago.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=AuthorizationRateDrop`) runs the read-only step of SSM document `pay-runbook-authorization-rate-drop`.
2. Split the drop by payment method, card country and issuer on the payments dashboard.
3. Check whether a routing or fraud rule changed in the last deploy.

### Actions

1. If one PSP is affected, follow `psp-degraded`.
2. If a routing change caused it, roll it back through the control plane.

### Escalation

Ticket to payments-core; it becomes a page through the PSP alert or the SLO burn.

### SSM document

`pay-runbook-authorization-rate-drop`

## unknown-state-payments-stale

Alert `UnknownStatePaymentsStale`, severity warning, owner payments-core-oncall, dashboard https://grafana.payments.internal/d/scheduler.

### Symptom

At least one payment has been in the unknown state for over 15 minutes, so sync did not resolve it.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=UnknownStatePaymentsStale`) runs the read-only step of SSM document `pay-runbook-unknown-state-payments-stale`.
2. Check the scheduler sync queue and the PSP status endpoint errors.

### Actions

1. Run a manual sync of the stale payments by reference id with document step `sync-stale` (read-only toward the PSP).
2. Never create a second charge for them.

### Escalation

Ticket to payments-core; page if the count grows above 100.

### SSM document

`pay-runbook-unknown-state-payments-stale`

## router5xx-rate-high

Alert `Router5xxRateHigh`, severity warning, owner payments-core-oncall, dashboard https://grafana.payments.internal/d/router.

### Symptom

More than 1% of the responses of a cell are 5xx.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=Router5xxRateHigh`) runs the read-only step of SSM document `pay-runbook-router5xx-rate-high`.
2. Split the errors by route and error source on the router dashboard.
3. Check the last rollout of the cell.

### Actions

1. Roll back the cell if the errors started with a rollout.
2. Close the cell with document step `close-cell` only on the commander's order.

### Escalation

Ticket to payments-core; the SLO burn alert is the page.

### SSM document

`pay-runbook-router5xx-rate-high`

## dlq-not-empty

Alert `DlqNotEmpty`, severity warning, owner payments-core-oncall, dashboard https://grafana.payments.internal/d/scheduler.

### Symptom

A DLQ holds messages for over 15 minutes.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=DlqNotEmpty`) runs the read-only step of SSM document `pay-runbook-dlq-not-empty`.
2. Read the failure reason of the newest message (sanitized, no card data).

### Actions

1. Fix the cause and replay the messages with document step `replay-dlq`; receivers deduplicate by event_id.

### Escalation

Ticket to payments-core.

### SSM document

`pay-runbook-dlq-not-empty`

## webhook-backlog-old

Alert `WebhookBacklogOld`, severity warning, owner payments-core-oncall, dashboard https://grafana.payments.internal/d/scheduler.

### Symptom

The oldest outgoing webhook in the queue is over 5 minutes old.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=WebhookBacklogOld`) runs the read-only step of SSM document `pay-runbook-webhook-backlog-old`.
2. Check whether one merchant endpoint blocks the workers.

### Actions

1. Throttle the slow merchant endpoint with document step `isolate-endpoint`.

### Escalation

Ticket to payments-core; the SLO burn alert is the page.

### SSM document

`pay-runbook-webhook-backlog-old`

## reconciliation-mismatch

Alert `ReconciliationMismatch`, severity warning, owner payments-core-oncall, dashboard https://grafana.payments.internal/d/payments.

### Symptom

The reconciliation job found payments whose amount differs from the PSP report.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=ReconciliationMismatch`) runs the read-only step of SSM document `pay-runbook-reconciliation-mismatch`.
2. List the mismatched reference ids from the reconciliation report (no card data).

### Actions

1. Hand the list to finance operations; refund a double charge through the PSP connector.

### Escalation

Ticket to payments-core and finance operations.

### SSM document

`pay-runbook-reconciliation-mismatch`

## migration-job-failed

Alert `MigrationJobFailed`, severity warning, owner payments-core-oncall, dashboard https://grafana.payments.internal/d/payments.

### Symptom

The migration Job of a rollout failed; the rollout does not continue.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=MigrationJobFailed`) runs the read-only step of SSM document `pay-runbook-migration-job-failed`.
2. Read the Job log and the pre-migration snapshot status.

### Actions

1. Fix the migration (expand-contract only) and run the Job again; `down.sql` is never applied in prod.

### Escalation

Ticket to the migration author; escalate to data-platform if it holds a lock.

### SSM document

`pay-runbook-migration-job-failed`

## retry-storm

Alert `RetryStorm`, severity warning, owner payments-core-oncall, dashboard https://grafana.payments.internal/d/payments.

### Symptom

More than 10% of the requests to a dependency are retries for 5 minutes.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=RetryStorm`) runs the read-only step of SSM document `pay-runbook-retry-storm`.
2. Find the dependency on the resilience panel and the error that triggers the retries.

### Actions

1. Fix or isolate the failing dependency; do not raise retry limits.
2. Check that only the layer closest to the dependency retries.

### Escalation

Ticket to payments-core; the chaos scenario `retry-storm` covers this.

### SSM document

`pay-runbook-retry-storm`

## retry-budget-exhausted-non-critical

Alert `RetryBudgetExhaustedNonCritical`, severity warning, owner payments-core-oncall, dashboard https://grafana.payments.internal/d/payments.

### Symptom

A dependency other than the locker and PSP sync used up its retry budget.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=RetryBudgetExhaustedNonCritical`) runs the read-only step of SSM document `pay-runbook-retry-budget-exhausted-non-critical`.
2. Check the dependency alerts of the data layer.

### Actions

1. Fix the dependency; the budget stays at 10%.

### Escalation

Ticket to the dependency owner.

### SSM document

`pay-runbook-retry-budget-exhausted-non-critical`
