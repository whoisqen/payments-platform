# CrashLoopBackOff

Layer compute, service kubernetes, severity critical, owner platform-oncall, failure mode `compute-crash-loop-back-off`.
Dashboard: https://grafana.payments.internal/d/kubernetes

## Symptom

A container of a payments namespace has been in CrashLoopBackOff for 5 minutes.

## Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=CrashLoopBackOff`) runs the read-only step of SSM document `pay-runbook-crash-loop-back-off` and gathers metrics, events and sanitized logs.
2. Read the last termination reason and exit code with `kubectl describe` through the diagnostic document.
3. Check the rollout that started it: ArgoCD history and the digest of the image.
4. Check dependencies in the logs: MemoryDB, Aurora, Vault, locker.

## Actions

1. If a rollout caused it, roll back the application in ArgoCD (step `rollback-app`).
2. If the cause is a dependency, follow the alert of that dependency instead.
3. If the pod is the drainer, check the Redis stream length at once: write-behind stops without it.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-crash-loop-back-off`), which is audited.

## Escalation

Escalate to the service owner (payments-core) when the cause is application code. Default chain: primary acknowledges within 5 min, the secondary is paged at 5 min and the incident commander at 15 min (section 20.6).

## SSM document

`pay-runbook-crash-loop-back-off`
