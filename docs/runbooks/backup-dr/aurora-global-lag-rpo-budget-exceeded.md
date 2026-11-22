# AuroraGlobalLagRpoBudgetExceeded

Layer backup-dr, service aurora, severity critical, owner data-platform-oncall, failure mode `backup-dr-aurora-global-lag-rpo-budget-exceeded`.
Dashboard: https://grafana.payments.internal/d/dr-switch

## Symptom

The lag to a recovery region is above the 10 s RPO budget.

## Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=AuroraGlobalLagRpoBudgetExceeded`) runs the read-only step of SSM document `pay-runbook-aurora-global-lag-rpo-budget-exceeded` and gathers metrics, events and sanitized logs.
2. Follow the diagnostics of `aurora-global-lag-high`.

## Actions

1. Pause batch writes; if the secondary link is broken, ask AWS support and record the exposure window for the reconciliation.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-aurora-global-lag-rpo-budget-exceeded`), which is audited.

## Escalation

Inform the commander: the exposure window must be recorded for the PSP reconciliation. Default chain: primary acknowledges within 5 min, the secondary is paged at 5 min and the incident commander at 15 min (section 20.6).

## SSM document

`pay-runbook-aurora-global-lag-rpo-budget-exceeded`
