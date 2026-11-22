# CertificateExpiryCritical

Layer network, service edge, severity critical, owner platform-oncall, failure mode `network-certificate-expiry-critical`.
Dashboard: https://grafana.payments.internal/d/edge

## Symptom

A certificate seen by the blackbox probes expires within 14 days; automatic renewal did not happen.

## Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=CertificateExpiryCritical`) runs the read-only step of SSM document `pay-runbook-certificate-expiry-critical` and gathers metrics, events and sanitized logs.
2. Check cert-manager `Certificate` and `CertificateRequest` status for the target.
3. Check the ACME or ACM validation DNS records (Route 53).
4. Check that the probe sees the same certificate from all three probe points.

## Actions

1. Force a renewal with the document step `renew-certificate` (cert-manager `cmctl renew` equivalent through the audited workflow).
2. If validation fails, fix the DNS record in Terraform and re-run.
3. Verify the new expiry from all probe points before closing.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-certificate-expiry-critical`), which is audited.

## Escalation

Escalate at once when less than 3 days remain. Default chain: primary acknowledges within 5 min, the secondary is paged at 5 min and the incident commander at 15 min (section 20.6).

## SSM document

`pay-runbook-certificate-expiry-critical`
