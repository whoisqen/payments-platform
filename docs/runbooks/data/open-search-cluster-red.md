# OpenSearchClusterRed

Layer data, service opensearch, severity critical, owner security-oncall, failure mode `data-open-search-cluster-red`.
Dashboard: https://grafana.payments.internal/d/data-stores

## Symptom

At least one primary shard of the audit domain is unassigned.

## Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=OpenSearchClusterRed`) runs the read-only step of SSM document `pay-runbook-open-search-cluster-red` and gathers metrics, events and sanitized logs.
2. Check the shard allocation explanation and the free storage of the domain.
3. Check that the Firehose delivery to S3 Object Lock still works: the archive is the source of truth.

## Actions

1. Free storage or add a data node with document step `scale-opensearch`.
2. Retry shard allocation after the cause is fixed.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-open-search-cluster-red`), which is audited.

## Escalation

Security on-call is informed because the audit trail is degraded; the S3 archive keeps the logs meanwhile. Default chain: primary acknowledges within 5 min, the secondary is paged at 5 min and the incident commander at 15 min (section 20.6).

## SSM document

`pay-runbook-open-search-cluster-red`
