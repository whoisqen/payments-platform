# Route53HealthCheckFailing

Layer network, service edge, severity critical, owner platform-oncall, failure mode `network-route53-health-check-failing`.
Dashboard: https://grafana.payments.internal/d/edge

## Symptom

A Route 53 health check has been unhealthy for 3 minutes.

## Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=Route53HealthCheckFailing`) runs the read-only step of SSM document `pay-runbook-route53-health-check-failing` and gathers metrics, events and sanitized logs.
2. Identify the endpoint of the health check in the Terraform output.
3. Compare with the blackbox probes of the same target from the three points.
4. Check the health check regions in the CloudWatch metric `HealthCheckPercentageHealthy`.

## Actions

1. If the endpoint is healthy, fix the health check path or its security group rule in Terraform.
2. If the endpoint is down, follow `region-down` or `global-accelerator-endpoint-unhealthy`.
3. Do not disable the health check to silence the alert.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-route53-health-check-failing`), which is audited.

## Escalation

Escalate to the commander if DNS failover has already moved traffic. Default chain: primary acknowledges within 5 min, the secondary is paged at 5 min and the incident commander at 15 min (section 20.6).

## SSM document

`pay-runbook-route53-health-check-failing`
