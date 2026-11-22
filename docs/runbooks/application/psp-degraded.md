# PSPDegraded

Layer application, service router, severity critical, owner payments-core-oncall, failure mode `application-psp-degraded`.
Dashboard: https://grafana.payments.internal/d/payments

## Symptom

More than 5% of the calls to one PSP end in technical errors (timeouts, 5xx, connection failures) for 5 minutes.

## Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=PSPDegraded`) runs the read-only step of SSM document `pay-runbook-psp-degraded` and gathers metrics, events and sanitized logs.
2. Check the PSP status page and the latency heatmap on the payments dashboard.
3. Check the circuit breaker state of the PSP and the routing weights.
4. Check whether the errors are limited to one cell or one payment method.

## Actions

1. Shift routing away from the PSP with document step `route-away-psp` (changes the routing weight through the control plane, audited).
2. Do not retry charges against the same PSP; timeouts become the unknown state and sync resolves them.
3. Re-enable the PSP in steps of 10% after its error rate stays under 1% for 15 minutes.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-psp-degraded`), which is audited.

## Escalation

Open the PSP incident channel; payments-core lead is informed when the PSP carries more than 30% of the volume. Default chain: primary acknowledges within 5 min, the secondary is paged at 5 min and the incident commander at 15 min (section 20.6).

## SSM document

`pay-runbook-psp-degraded`
