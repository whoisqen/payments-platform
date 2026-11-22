# BreakGlassRoleUsed

Layer security-pci, service cloudtrail, severity security, owner security-oncall, failure mode `security-pci-break-glass-role-used`.
Dashboard: https://grafana.payments.internal/d/edge

## Symptom

A principal assumed the BreakGlass role.

## Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=BreakGlassRoleUsed`) runs the read-only step of SSM document `pay-runbook-break-glass-role-used` and gathers metrics, events and sanitized logs.
2. Match the session with the incident number in the break-glass request.

## Actions

1. If there is no approved request, revoke the session and treat it as a compromise.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-break-glass-role-used`), which is audited.

## Escalation

The security on-call confirms the use against the incident; every use needs a post-use review. Default chain: the security on-call acknowledges within 5 min and opens an incident; the incident commander joins at 15 min; PCI-relevant findings are reported to the compliance owner the same day.

## SSM document

`pay-runbook-break-glass-role-used`
