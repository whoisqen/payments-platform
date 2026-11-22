# RootAccountLogin

Layer security-pci, service cloudtrail, severity security, owner security-oncall, failure mode `security-pci-root-account-login`.
Dashboard: https://grafana.payments.internal/d/edge

## Symptom

CloudTrail recorded a root console login or API call.

## Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=RootAccountLogin`) runs the read-only step of SSM document `pay-runbook-root-account-login` and gathers metrics, events and sanitized logs.
2. Read the event: source IP, MFA used, account.
3. Check whether a break-glass procedure was opened for it.

## Actions

1. If it is not an approved break-glass, reset the root credentials and MFA with the account owner and review all actions of the session.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-root-account-login`), which is audited.

## Escalation

Open a security incident at once. Default chain: the security on-call acknowledges within 5 min and opens an incident; the incident commander joins at 15 min; PCI-relevant findings are reported to the compliance owner the same day.

## SSM document

`pay-runbook-root-account-login`
