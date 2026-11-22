# RetryBudgetExhausted

Layer application, service resilience, severity critical, owner payments-core-oncall, failure mode `application-retry-budget-exhausted`.
Dashboard: https://grafana.payments.internal/d/payments

## Symptom

The retry budget (10% of normal traffic) of the locker or of PSP sync is used up.

## Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=RetryBudgetExhausted`) runs the read-only step of SSM document `pay-runbook-retry-budget-exhausted` and gathers metrics, events and sanitized logs.
2. Check the dependency health: locker errors, PSP sync errors, circuit breaker state.
3. Check `retry_total` by dependency for the amplification source.

## Actions

1. Restore the dependency first; do not raise the budget.
2. If the PSP sync budget is exhausted, unknown-state payments stay unresolved: follow `psp-degraded`.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-retry-budget-exhausted`), which is audited.

## Escalation

Escalate to the commander if the locker is the dependency. Default chain: primary acknowledges within 5 min, the secondary is paged at 5 min and the incident commander at 15 min (section 20.6).

## SSM document

`pay-runbook-retry-budget-exhausted`
