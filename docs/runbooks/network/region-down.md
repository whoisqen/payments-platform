# RegionDown

Layer network, service edge, severity critical, owner platform-oncall, failure mode `network-region-down`.
Dashboard: https://grafana.payments.internal/d/edge

## Symptom

Two or more of the three probe points (us-east-1 and two external providers) cannot reach the Frankfurt health endpoint for 2 minutes. This is the detection signal of the automatic switch to the us-east-1 hot standby; inhibits component alerts of the region.

## Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=RegionDown`) runs the read-only step of SSM document `pay-runbook-region-down` and gathers metrics, events and sanitized logs.
2. Check `probe_success` per `probe_point`: if only one point fails the cause is the probe path, not the region.
3. Check AWS Health and the status of Global Accelerator endpoint groups on the edge dashboard.
4. Check the Frankfurt router `up` and ingress NLB target health from the platform dashboard.

## Actions

1. If the region is confirmed down, the on-call starts the switch: SSM document `pay-runbook-region-down` fences Frankfurt automatically and waits for one on-call confirmation (ADR-015).
2. Do not confirm while a single probe point is the only failing one; a false switch with two writers can charge a payment twice.
3. If Frankfurt recovers before confirmation, cancel the switch in the document and keep fencing off.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-region-down`), which is audited.

## Escalation

Incident commander is added at once; confirmation of the switch needs the commander and the primary. Default chain: primary acknowledges within 5 min, the secondary is paged at 5 min and the incident commander at 15 min (section 20.6).

## SSM document

`pay-runbook-region-down`
