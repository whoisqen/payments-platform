# GuardDutyHighFinding

Layer security-pci, service guardduty, severity security, owner security-oncall, failure mode `security-pci-guard-duty-high-finding`.
Dashboard: https://grafana.payments.internal/d/edge

## Symptom

A GuardDuty finding of severity High was raised in the last 15 minutes.

## Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=GuardDutyHighFinding`) runs the read-only step of SSM document `pay-runbook-guard-duty-high-finding` and gathers metrics, events and sanitized logs.
2. Open the finding in the audit account and read the resource, the actor and the API calls.
3. Check CloudTrail for the same principal over the last 24 hours.

## Actions

1. Isolate the resource with document step `isolate-resource` (security group quarantine, no deletion).
2. Revoke the session of the principal; rotate its keys through Vault.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-guard-duty-high-finding`), which is audited.

## Escalation

Open a security incident at once; the PCI incident response plan applies when the account is in the CDE. Default chain: the security on-call acknowledges within 5 min and opens an incident; the incident commander joins at 15 min; PCI-relevant findings are reported to the compliance owner the same day.

## SSM document

`pay-runbook-guard-duty-high-finding`
