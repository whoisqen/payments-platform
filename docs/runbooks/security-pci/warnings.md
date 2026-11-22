# security-pci: non-paging alerts

Each section is the runbook of one ticket or Slack alert; the alert annotation links to its anchor. A ticket is handled in working hours; if the condition persists past the stated escalation, the owner raises it to the on-call.

## cde-network-policy-changed

Alert `CdeNetworkPolicyChanged`, severity warning, owner security-oncall, dashboard https://grafana.payments.internal/d/edge.

### Symptom

A security group, Network Firewall rule or NACL of the CDE changed.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=CdeNetworkPolicyChanged`) runs the read-only step of SSM document `pay-runbook-cde-network-policy-changed`.
2. Match the change with the Atlantis apply that carried the pull request.

### Actions

1. If there is no matching pull request, revert from Git and raise a security incident.

### Escalation

Reviewed the same day by the security on-call.

### SSM document

`pay-runbook-cde-network-policy-changed`

## kms-key-rotation-overdue

Alert `KmsKeyRotationOverdue`, severity warning, owner security-oncall, dashboard https://grafana.payments.internal/d/edge.

### Symptom

The rotation of a KMS key did not happen on schedule.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=KmsKeyRotationOverdue`) runs the read-only step of SSM document `pay-runbook-kms-key-rotation-overdue`.
2. Check whether automatic rotation is enabled on the key and the key policy allows it.

### Actions

1. Enable rotation through Terraform or rotate the data key through the locker rotation job.

### Escalation

Ticket to security; escalate to the compliance owner after 7 days.

### SSM document

`pay-runbook-kms-key-rotation-overdue`

## kyverno-audit-violations

Alert `KyvernoAuditViolations`, severity warning, owner security-oncall, dashboard https://grafana.payments.internal/d/edge.

### Symptom

A policy in audit mode reports failing resources.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=KyvernoAuditViolations`) runs the read-only step of SSM document `pay-runbook-kyverno-audit-violations`.
2. List the failing resources per policy from the Kyverno policy report.

### Actions

1. Fix the manifests through pull requests before the policy moves to enforce.

### Escalation

Ticket to the owner of the workload.

### SSM document

`pay-runbook-kyverno-audit-violations`
