# LockerErrorRateHigh

Layer application, service locker, severity critical, owner payments-core-oncall, failure mode `application-locker-error-rate-high`.
Dashboard: https://grafana.payments.internal/d/locker

## Symptom

More than 1% of the locker responses are 5xx.

## Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=LockerErrorRateHigh`) runs the read-only step of SSM document `pay-runbook-locker-error-rate-high` and gathers metrics, events and sanitized logs.
2. Check locker pods, KMS errors and Aurora connectivity of the locker database.
3. Check the router-to-locker retry budget on the locker dashboard.

## Actions

1. If KMS throttles, follow the KMS runbook of the security team.
2. Scale the locker out through the HPA step `scale-locker` if CPU bound.
3. Do not log request bodies while debugging: the locker handles PAN.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-locker-error-rate-high`), which is audited.

## Escalation

Page the security on-call too if the errors are authorization or certificate related (CDE component). Default chain: primary acknowledges within 5 min, the secondary is paged at 5 min and the incident commander at 15 min (section 20.6).

## SSM document

`pay-runbook-locker-error-rate-high`
