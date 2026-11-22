# SyntheticPaymentFailing

Layer application, service router, severity critical, owner payments-core-oncall, failure mode `application-synthetic-payment-failing`.
Dashboard: https://grafana.payments.internal/d/payments

## Symptom

The synthetic payment against the test PSP, sent every 60 seconds, failed from two of three probe points for 3 minutes.

## Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=SyntheticPaymentFailing`) runs the read-only step of SSM document `pay-runbook-synthetic-payment-failing` and gathers metrics, events and sanitized logs.
2. Read the failing step in the probe result: create, confirm or retrieve.
3. Check the router 5xx rate and the test PSP status.
4. Compare with `region-down`.

## Actions

1. Follow the alert of the failing component.
2. If the test PSP is the only failure, check its connector; it does not affect real merchants.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-synthetic-payment-failing`), which is audited.

## Escalation

Escalate to the commander if the real authorization rate also drops. Default chain: primary acknowledges within 5 min, the secondary is paged at 5 min and the incident commander at 15 min (section 20.6).

## SSM document

`pay-runbook-synthetic-payment-failing`
