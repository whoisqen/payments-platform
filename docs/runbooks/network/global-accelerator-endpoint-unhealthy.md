# GlobalAcceleratorEndpointUnhealthy

Layer network, service edge, severity critical, owner platform-oncall, failure mode `network-global-accelerator-endpoint-unhealthy`.
Dashboard: https://grafana.payments.internal/d/edge

## Symptom

The endpoint group of the payments accelerator reports zero healthy endpoints for 3 minutes.

## Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=GlobalAcceleratorEndpointUnhealthy`) runs the read-only step of SSM document `pay-runbook-global-accelerator-endpoint-unhealthy` and gathers metrics, events and sanitized logs.
2. Check the NLB target group health of the affected endpoint group.
3. Check router pod readiness per cell: a failed readiness probe removes the NLB targets.
4. Compare with `RegionDown`: if it fires too, treat it as a region event.

## Actions

1. If a bad rollout caused it, roll back the cell through ArgoCD (document `pay-runbook-global-accelerator-endpoint-unhealthy`, step `rollback-cell`).
2. If one AZ is affected, cordon the AZ in the NLB with the document step `drain-az`.
3. Keep the endpoint group weight unchanged unless the commander orders a switch.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-global-accelerator-endpoint-unhealthy`), which is audited.

## Escalation

Escalate to the AWS Enterprise support case after 15 minutes without recovery. Default chain: primary acknowledges within 5 min, the secondary is paged at 5 min and the incident commander at 15 min (section 20.6).

## SSM document

`pay-runbook-global-accelerator-endpoint-unhealthy`
