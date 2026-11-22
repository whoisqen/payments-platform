# Payment status read SLO burn

Alerts `PaymentsStatusReadBurnFast` (14.4x), `...BurnSlow` (6x) page; `...BurnTicket` (1x) opens a ticket.
SLO 99.95% of `GET /payments/{id}` under 50 ms and without a 5xx; the budget is 21.6 minutes per 30 days. Dashboard: https://grafana.payments.internal/d/slo-overview

## Symptom

Status reads are slow or fail. Reads are served from MemoryDB first and from Aurora after the drain, so the cause is usually the cache or the database.

## Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=PaymentsStatusReadBurnFast`) runs the read-only step of SSM document `pay-runbook-payment-status-read`.
2. Check MemoryDB latency, memory and evictions, and the cache warm ratio of the cell.
3. Check Aurora reader lag and connections on the data-stores dashboard.

## Actions

1. If the cache is cold after a replacement, restart the warm-up with step `rewarm-cache`.
2. If MemoryDB is saturated, follow `memory-db-memory-critical`.
3. If Aurora readers are slow, follow the Aurora runbooks; roll back a rollout that started the burn.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-payment-status-read`), which is audited.

## Escalation

Primary acknowledges within 5 minutes, the secondary is paged at 5 minutes and the incident commander at 15 minutes (section 20.6).

## SSM document

`pay-runbook-payment-status-read`
