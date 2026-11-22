# MemoryDbEvictions

Layer data, service memorydb, severity critical, owner data-platform-oncall, failure mode `data-memory-db-evictions`.
Dashboard: https://grafana.payments.internal/d/data-stores

## Symptom

MemoryDB evicts keys; the policy should be `noeviction`, so any eviction is a configuration or capacity fault.

## Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=MemoryDbEvictions`) runs the read-only step of SSM document `pay-runbook-memory-db-evictions` and gathers metrics, events and sanitized logs.
2. Check the parameter group `maxmemory-policy` of the cluster.
3. Check which key prefix is evicted from the slow log and memory stats.

## Actions

1. Restore `noeviction` through Terraform if the policy drifted.
2. Scale out as in `memory-db-memory-critical`.
3. Run a reconciliation of unknown-state payments with the PSP after the incident.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-memory-db-evictions`), which is audited.

## Escalation

Escalate to the commander at once: possible loss of idempotency keys. Default chain: primary acknowledges within 5 min, the secondary is paged at 5 min and the incident commander at 15 min (section 20.6).

## SSM document

`pay-runbook-memory-db-evictions`
