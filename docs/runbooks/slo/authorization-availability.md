# Authorization availability SLO burn

Alerts `PaymentsAuthorizationAvailabilityBurnFastest` (50x, 5 min / 1 min), `...BurnFast` (14.4x, 1 h / 5 min), `...BurnSlow` (6x, 6 h / 30 min) page; `...BurnTicket` (1x, 3 d / 6 h) opens a ticket.
SLO 99.99% of `POST /payments/{id}/confirm` without a platform-side 5xx; the budget is 4.3 minutes per 30 days. Dashboard: https://grafana.payments.internal/d/slo-overview

## Symptom

The router answers `confirm` with 5xx attributable to the platform (`fault="platform"`); PSP errors and declines are not counted. At 50x the whole monthly budget is gone in under an hour.

## Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=PaymentsAuthorizationAvailabilityBurnFast`) runs the read-only step of SSM document `pay-runbook-authorization-availability`.
2. Split the 5xx by `cell`, `route`, `error` on the router dashboard: one cell means a cell problem, all cells mean a shared dependency (locker, MemoryDB, Vault).
3. Check the last rollout in ArgoCD and the alerts `locker-error-rate-high`, `memory-db-memory-critical`, `drain-lag-high`.

## Actions

1. If a rollout started the burn, roll back the application in ArgoCD (document step `rollback-app`).
2. If one cell is bad, close it to new merchants with step `close-cell` on the commander's order; the merchant-to-cell map moves traffic to the other cells.
3. If a dependency is the cause, follow the runbook of its alert.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-authorization-availability`), which is audited.

## Escalation

Primary acknowledges within 5 minutes, the secondary is paged at 5 minutes and the incident commander at 15 minutes (section 20.6). Open an incident for any page of this SLO.

## SSM document

`pay-runbook-authorization-availability`
