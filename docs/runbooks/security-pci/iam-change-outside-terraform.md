# IamChangeOutsideTerraform

Layer security-pci, service cloudtrail, severity security, owner security-oncall, failure mode `security-pci-iam-change-outside-terraform`.
Dashboard: https://grafana.payments.internal/d/edge

## Symptom

CloudTrail recorded an IAM write from a principal that is not the Atlantis role.

## Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=IamChangeOutsideTerraform`) runs the read-only step of SSM document `pay-runbook-iam-change-outside-terraform` and gathers metrics, events and sanitized logs.
2. Read the actor and the change; compare with open pull requests.

## Actions

1. Revert the change by running the Terraform plan for the account (audited workflow) and review the actor's access.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-iam-change-outside-terraform`), which is audited.

## Escalation

Escalate to an incident if the actor is a human outside break-glass. Default chain: the security on-call acknowledges within 5 min and opens an incident; the incident commander joins at 15 min; PCI-relevant findings are reported to the compliance owner the same day.

## SSM document

`pay-runbook-iam-change-outside-terraform`
