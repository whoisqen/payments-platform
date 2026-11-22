# Merchant webhook delivery SLO burn

Alerts `PaymentsWebhookDeliveryBurnFast` (14.4x), `...BurnSlow` (6x) page; `...BurnTicket` (1x) opens a ticket.
SLO 99.9% of outgoing webhooks delivered under 60 seconds after the event. Dashboard: https://grafana.payments.internal/d/slo-overview

## Symptom

Events reach merchants late or not at all: the scheduler queue is delayed, merchant endpoints fail, or the PSP callbacks that trigger the events are late.

## Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=PaymentsWebhookDeliveryBurnFast`) runs the read-only step of SSM document `pay-runbook-merchant-webhook-delivery`.
2. Check the oldest queue age and the DLQ depth on the scheduler dashboard.
3. Check whether a few merchant endpoints cause most failures (timeouts at the 10 s limit).

## Actions

1. If the workers are saturated, scale the consumers with step `scale-scheduler`.
2. If a few merchant endpoints block the workers, isolate them with step `isolate-endpoint`; they continue on the retry schedule 1 min, 5 min, 30 min, 2 h, 12 h.
3. Replay the DLQ after the cause is fixed with step `replay-dlq`; receivers deduplicate by `event_id`.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-merchant-webhook-delivery`), which is audited.

## Escalation

Primary acknowledges within 5 minutes, the secondary is paged at 5 minutes and the incident commander at 15 minutes (section 20.6).

## SSM document

`pay-runbook-merchant-webhook-delivery`
