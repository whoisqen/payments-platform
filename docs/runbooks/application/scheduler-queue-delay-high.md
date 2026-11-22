# SchedulerQueueDelayHigh

Layer application, service scheduler, severity critical, owner payments-core-oncall, failure mode `application-scheduler-queue-delay-high`.
Dashboard: https://grafana.payments.internal/d/scheduler

## Symptom

Tasks wait in the scheduler queue for over 10 minutes.

## Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=SchedulerQueueDelayHigh`) runs the read-only step of SSM document `pay-runbook-scheduler-queue-delay-high` and gathers metrics, events and sanitized logs.
2. Check the consumer pods and the task kinds in the queue on the scheduler dashboard.
3. Check PSP error rates: sync tasks retry on errors.

## Actions

1. Scale the consumers with document step `scale-scheduler`.
2. Move the failing task kind to the DLQ if it blocks the rest.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-scheduler-queue-delay-high`), which is audited.

## Escalation

Escalate to payments-core lead when unknown-state payments are older than 15 minutes. Default chain: primary acknowledges within 5 min, the secondary is paged at 5 min and the incident commander at 15 min (section 20.6).

## SSM document

`pay-runbook-scheduler-queue-delay-high`
