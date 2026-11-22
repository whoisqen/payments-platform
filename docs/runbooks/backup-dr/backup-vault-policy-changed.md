# BackupVaultPolicyChanged

Layer backup-dr, service aws-backup, severity security, owner security-oncall, failure mode `backup-dr-backup-vault-policy-changed`.
Dashboard: https://grafana.payments.internal/d/backup

## Symptom

EventBridge recorded a change of a backup vault policy or Vault Lock.

## Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=BackupVaultPolicyChanged`) runs the read-only step of SSM document `pay-runbook-backup-vault-policy-changed` and gathers metrics, events and sanitized logs.
2. Compare the change with the Atlantis apply of an approved pull request.

## Actions

1. If unapproved, revert from Git with the audited workflow and revoke the actor's session.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-backup-vault-policy-changed`), which is audited.

## Escalation

Open a security incident if the actor is not the automation role. Default chain: the security on-call acknowledges within 5 min and opens an incident; the incident commander joins at 15 min; PCI-relevant findings are reported to the compliance owner the same day.

## SSM document

`pay-runbook-backup-vault-policy-changed`
