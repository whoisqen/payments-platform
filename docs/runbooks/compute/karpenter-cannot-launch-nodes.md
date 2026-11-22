# KarpenterCannotLaunchNodes

Layer compute, service kubernetes, severity critical, owner platform-oncall, failure mode `compute-karpenter-cannot-launch-nodes`.
Dashboard: https://grafana.payments.internal/d/kubernetes

## Symptom

Karpenter node creation calls keep failing: capacity, quota or an instance family problem.

## Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=KarpenterCannotLaunchNodes`) runs the read-only step of SSM document `pay-runbook-karpenter-cannot-launch-nodes` and gathers metrics, events and sanitized logs.
2. Read `NodeClaim` conditions and the Karpenter log for `InsufficientInstanceCapacity` or quota errors.
3. Check the NodePool requirements: instance families r7g, r6g, m7g, r7i, r6i across the three AZs.
4. Check EC2 service quotas for the vCPU classes in use.

## Actions

1. Widen the NodePool instance families or AZs through a PR (step `widen-nodepool`).
2. Ask for a quota increase through the Terraform quota module.
3. During a switch this is the trigger of plan B: after 10 minutes without capacity the runbook starts compute in us-east-2.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-karpenter-cannot-launch-nodes`), which is audited.

## Escalation

Escalate to the commander when it occurs during a switch or a Black Friday peak. Default chain: primary acknowledges within 5 min, the secondary is paged at 5 min and the incident commander at 15 min (section 20.6).

## SSM document

`pay-runbook-karpenter-cannot-launch-nodes`
