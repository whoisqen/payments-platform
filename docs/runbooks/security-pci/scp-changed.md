# ScpChanged

Layer security-pci, service cloudtrail, severity security, owner security-oncall, failure mode `security-pci-scp-changed`.
Dashboard: https://grafana.payments.internal/d/edge

## Symptom

CloudTrail recorded a change of an SCP or its attachment.

## Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=ScpChanged`) runs the read-only step of SSM document `pay-runbook-scp-changed` and gathers metrics, events and sanitized logs.
2. Compare the change with the pull request that Atlantis applied.

## Actions

1. If there is no matching pull request, revert the SCP from Git with the audited workflow and investigate the actor.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-scp-changed`), which is audited.

## Escalation

Open a security incident if the change was not made by the automation role. Default chain: the security on-call acknowledges within 5 min and opens an incident; the incident commander joins at 15 min; PCI-relevant findings are reported to the compliance owner the same day.

## SSM document

`pay-runbook-scp-changed`
