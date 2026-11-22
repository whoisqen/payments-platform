# NatPortAllocationErrors

Layer network, service egress, severity critical, owner platform-oncall, failure mode `network-nat-port-allocation-errors`.
Dashboard: https://grafana.payments.internal/d/edge

## Symptom

The NAT gateway reports port allocation errors for 5 minutes; outbound connections to PSPs time out.

## Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=NatPortAllocationErrors`) runs the read-only step of SSM document `pay-runbook-nat-port-allocation-errors` and gathers metrics, events and sanitized logs.
2. Check `aws_natgateway_active_connection_count` and the top destinations in the VPC flow logs.
3. Check for a retry storm: `retry_total` by dependency on the application dashboard.
4. Check whether a recent deploy raised the connection count per pod.

## Actions

1. Spread egress over more NAT gateways or add EIPs through the Terraform change prepared in `infra/` (document step `scale-egress`).
2. If a retry storm is the cause, open the circuit breaker of the PSP with `pay-runbook-nat-port-allocation-errors` step `open-breaker`.
3. Never raise retries to compensate; a charge is never retried.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-nat-port-allocation-errors`), which is audited.

## Escalation

Platform primary owns it; payments-core is informed because payments move to the unknown state and sync resolves them. Default chain: primary acknowledges within 5 min, the secondary is paged at 5 min and the incident commander at 15 min (section 20.6).

## SSM document

`pay-runbook-nat-port-allocation-errors`
