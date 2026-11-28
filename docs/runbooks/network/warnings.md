# network: non-paging alerts

Each section is the runbook of one ticket or Slack alert; the alert annotation links to its anchor. A ticket is handled in working hours; if the condition persists past the stated escalation, the owner raises it to the on-call.

## psp-mtls-cert-expiring30d

Alert `PspMtlsCertExpiring30d`, severity warning, owner platform-oncall, dashboard https://grafana.payments.internal/d/edge.

### Symptom

The mTLS client certificate used towards a PSP expires within 30 days.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=PspMtlsCertExpiring30d`) runs the read-only step of SSM document `pay-runbook-psp-mtls-cert-expiring30d`.
2. Check the cert-manager `Certificate` for the PSP and its issuer.
3. Check whether the PSP must register the new certificate first.

### Actions

1. Request the renewal; if the PSP needs a registration, open the ticket with the PSP contact from the connector record.
2. Roll the secret through Vault and verify with a test call from stage.

### Escalation

Raise to platform on-call when less than 7 days remain.

### SSM document

`pay-runbook-psp-mtls-cert-expiring30d`

## waf-blocked-requests-high

Alert `WafBlockedRequestsHigh`, severity warning, owner security-oncall, dashboard https://grafana.payments.internal/d/edge.

### Symptom

The WAF has been blocking over 100 requests per second for 10 minutes.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=WafBlockedRequestsHigh`) runs the read-only step of SSM document `pay-runbook-waf-blocked-requests-high`.
2. Check the top rules and source ASNs in the WAF logs (CloudWatch Logs Insights on the WAF log group).
3. Check the authorization rate: a drop with high blocks suggests false positives.

### Actions

1. If it is an attack, add a rate-based rule through Terraform.
2. If a rule blocks legitimate merchants, switch it to count mode through a PR.

### Escalation

Security on-call is informed in working hours; escalate to page if the authorization rate drops.

### SSM document

`pay-runbook-waf-blocked-requests-high`

## network-firewall-drops-high

Alert `NetworkFirewallDropsHigh`, severity warning, owner platform-oncall, dashboard https://grafana.payments.internal/d/edge.

### Symptom

The egress firewall drops over 1000 packets per second for 10 minutes.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=NetworkFirewallDropsHigh`) runs the read-only step of SSM document `pay-runbook-network-firewall-drops-high`.
2. Read the drop reasons in the firewall alert log for the top destinations.
3. Compare destinations with the PSP domain allow list in the policy repository.

### Actions

1. Add a missing PSP domain through a PR to the firewall policy.
2. If the drops are an exfiltration attempt, hand over to security.

### Escalation

Platform ticket; escalate to security if the destinations are unknown.

### SSM document

`pay-runbook-network-firewall-drops-high`

## cloud-front5xx-high

Alert `CloudFront5xxHigh`, severity warning, owner platform-oncall, dashboard https://grafana.payments.internal/d/edge.

### Symptom

More than 5% of responses of a CloudFront distribution are 5xx.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=CloudFront5xxHigh`) runs the read-only step of SSM document `pay-runbook-cloud-front5xx-high`.
2. Check the origin health and the origin response time.
3. Check recent changes of the distribution in the Terraform plan history.

### Actions

1. Fix the origin or roll back the last origin change.
2. Invalidate the cache only if stale error responses are cached.

### Escalation

Ticket to platform; the control-center is outside the CDE and outside the payment path.

### SSM document

`pay-runbook-cloud-front5xx-high`
