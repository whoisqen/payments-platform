# RestoreTestFailed

Layer backup-dr, service restore-verifier, severity critical, owner data-platform-oncall, failure mode `backup-dr-restore-test-failed`.
Dashboard: https://grafana.payments.internal/d/backup

## Symptom

The daily automatic restore into the scratch environment failed or its data check did not pass.

## Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=RestoreTestFailed`) runs the read-only step of SSM document `pay-runbook-restore-test-failed` and gathers metrics, events and sanitized logs.
2. Read the restore automation log: restore, warm-up (pg_prewarm), row-count and checksum steps.
3. Check quotas and KMS access of the restore role.

## Actions

1. Fix the cause and rerun the document `pay-runbook-restore-test-failed` for the store.
2. Until it passes, take an extra on-demand backup and keep the previous passing one.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-restore-test-failed`), which is audited.

## Escalation

Escalate to the commander if the production restore path itself is broken. Default chain: primary acknowledges within 5 min, the secondary is paged at 5 min and the incident commander at 15 min (section 20.6).

## SSM document

`pay-runbook-restore-test-failed`
