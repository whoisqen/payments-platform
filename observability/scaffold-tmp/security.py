from common import a, gap

L = "security-pci"
S = "security"
EV = 'security_events_total{event="%s"}'


def event(name, ev, svc, comp, summary, failure, impact, sym, diag, act, esc, extra=""):
    a(layer=L, group="detection", name=name, sev="security", team=S, svc=svc, comp=comp, dash="edge",
      expr=f'sum(increase(security_events_total{{event="{ev}"}}[10m])) > 0', f="0m", sum=summary,
      series=[(EV % ev, "0+1x{n}", "0+0x{n}")], labels={},
      failure=failure, impact=impact, sym=sym, diag=diag, act=act, esc=esc)


a(layer=L, group="detection", name="GuardDutyHighFinding", sev="security", team=S, svc="guardduty", comp="guardduty", dash="edge",
  expr='sum by (account) (increase(guardduty_findings_total{severity="high"}[15m])) > 0', f="0m",
  sum="GuardDuty reports a high-severity finding",
  series=[('guardduty_findings_total{severity="high",account="cde-prod"}', "0+1x{n}", "0+0x{n}")], labels={"account": "cde-prod"},
  failure="GuardDuty high finding", impact="possible compromise of an AWS account or workload",
  sym="A GuardDuty finding of severity High was raised in the last 15 minutes.",
  diag=["Open the finding in the audit account and read the resource, the actor and the API calls.", "Check CloudTrail for the same principal over the last 24 hours."],
  act=["Isolate the resource with document step `isolate-resource` (security group quarantine, no deletion).", "Revoke the session of the principal; rotate its keys through Vault."],
  esc="Open a security incident at once; the PCI incident response plan applies when the account is in the CDE.")

a(layer=L, group="detection", name="GuardDutyRuntimeCdeFinding", sev="security", team=S, svc="guardduty", comp="runtime-monitoring", dash="edge",
  expr='sum by (cluster) (increase(guardduty_runtime_findings_total{cde="true"}[15m])) > 0', f="0m",
  sum="GuardDuty Runtime Monitoring raised a finding in the CDE",
  series=[('guardduty_runtime_findings_total{cde="true",cluster="cde-prod-euc1"}', "0+1x{n}", "0+0x{n}")], labels={"cluster": "cde-prod-euc1"},
  failure="runtime threat in the CDE", impact="possible code execution or card data access inside a CDE pod or node",
  sym="Runtime Monitoring detected suspicious behaviour in a CDE cluster.",
  diag=["Read the finding: container, process, network connection.", "Check Kyverno audit results and recent deploys of that workload."],
  act=["Cordon the node and scale the workload to zero with document step `quarantine-workload`; keep the node for forensics.", "Do not copy data out of the CDE; forensic tooling runs inside it."],
  esc="Open a security incident; the compliance owner is informed the same day.")

a(layer=L, group="detection", name="PanDetectedInLogs", sev="security", team=S, svc="otel-collector", comp="pan-detection", dash="edge",
  expr="sum by (source) (increase(pan_detected_total[15m])) > 0", f="0m",
  sum="A PAN pattern was detected in telemetry or logs",
  series=[('pan_detected_total{source="logs"}', "0+1x{n}", "0+0x{n}")], labels={"source": "logs"},
  failure="PAN in logs", impact="PCI DSS 3.3 violation: card data left the CDE; the collector masks it but the origin must be fixed",
  sym="The redaction processor or Macie found a PAN pattern in logs, traces or metrics.",
  diag=["Find the emitting service and field from the collector attribute counters (never from the value).", "Check the last deploy of that service for a new log statement."],
  act=["Roll back or patch the emitting code; keep the masking rule on.", "Purge the affected log streams in Loki and the S3 archive with the security document step `purge-logs` (needs two approvals)."],
  esc="Open a security incident and a PCI-impact note; never paste the matched value into a ticket.")

event("RootAccountLogin", "root_login", "cloudtrail", "iam", "An AWS root account login happened",
      "root account login", "the root account bypasses every control; PCI DSS 8.2",
      "CloudTrail recorded a root console login or API call.",
      ["Read the event: source IP, MFA used, account.", "Check whether a break-glass procedure was opened for it."],
      ["If it is not an approved break-glass, reset the root credentials and MFA with the account owner and review all actions of the session."],
      "Open a security incident at once.")

event("BreakGlassRoleUsed", "break_glass", "cloudtrail", "iam", "The BreakGlass role was assumed",
      "break-glass role used", "emergency access to the CDE; must match an approved incident",
      "A principal assumed the BreakGlass role.",
      ["Match the session with the incident number in the break-glass request."],
      ["If there is no approved request, revoke the session and treat it as a compromise."],
      "The security on-call confirms the use against the incident; every use needs a post-use review.")

event("ScpChanged", "scp_change", "cloudtrail", "organizations", "A service control policy changed",
      "SCP change", "guardrails of the organization were modified; PCI DSS 1.2 and 7.2",
      "CloudTrail recorded a change of an SCP or its attachment.",
      ["Compare the change with the pull request that Atlantis applied."],
      ["If there is no matching pull request, revert the SCP from Git with the audited workflow and investigate the actor."],
      "Open a security incident if the change was not made by the automation role.")

event("IamChangeOutsideTerraform", "iam_change_outside_terraform", "cloudtrail", "iam", "An IAM change was made outside Terraform",
      "IAM drift by hand", "permissions changed without review; PCI DSS 7.2.4",
      "CloudTrail recorded an IAM write from a principal that is not the Atlantis role.",
      ["Read the actor and the change; compare with open pull requests."],
      ["Revert the change by running the Terraform plan for the account (audited workflow) and review the actor's access."],
      "Escalate to an incident if the actor is a human outside break-glass.")

a(layer=L, group="detection", name="VaultSealed", sev="critical", team=S, svc="vault", comp="vault", dash="edge",
  expr="max by (cluster) (vault_core_unsealed) == 0", f="1m",
  sum="Vault is sealed",
  series=[('vault_core_unsealed{cluster="vault-main"}', "0x{n}", "1x{n}")],
  failure="Vault sealed", impact="services cannot read secrets or database credentials after their lease expires; the locker key access is affected",
  sym="Vault reports it is sealed.",
  diag=["Check the Vault pod logs for the cause: restart, node loss, auto-unseal KMS error.", "Check the KMS key policy used for auto-unseal."],
  act=["Auto-unseal normally recovers it; if KMS access failed, restore the key grant through Terraform.", "If a node restore is needed, use the latest Raft snapshot (hourly) with document step `restore-vault`."],
  esc="Escalate to the commander if it stays sealed for 10 minutes.")

a(layer=L, group="detection", name="VaultAuditDeviceFailing", sev="critical", team=S, svc="vault", comp="vault-audit", dash="edge",
  expr="sum by (cluster) (increase(vault_audit_log_request_failure[5m])) > 0", f="2m",
  sum="Vault audit device fails",
  series=[('vault_audit_log_request_failure{cluster="vault-main"}', "0+1x{n}", "0+0x{n}")], labels={"cluster": "vault-main"},
  failure="Vault audit device failing", impact="Vault stops answering requests when no audit device can write; PCI DSS 10.2",
  sym="Writes to the Vault audit device fail.",
  diag=["Check the audit device target (S3 or socket) and its credentials.", "Check the disk of the audit sink."],
  act=["Fix the audit sink; do not disable the audit device.", "Enable a second audit device through the Vault-as-code PR to avoid a single point of failure."],
  esc="Escalate to the commander if secret reads start failing.")

a(layer=L, group="detection", name="CdeNetworkPolicyChanged", sev="warning", team=S, svc="cloudtrail", comp="network-policy", dash="edge",
  expr='sum(increase(security_events_total{event="cde_network_change"}[10m])) > 0', f="0m",
  sum="A CDE network control changed (security group, firewall or NACL)",
  series=[(EV % "cde_network_change", "0+1x{n}", "0+0x{n}")], labels={},
  failure="CDE network policy change", impact="segmentation of the CDE may be weakened; PCI DSS 1.2.2",
  sym="A security group, Network Firewall rule or NACL of the CDE changed.",
  diag=["Match the change with the Atlantis apply that carried the pull request."],
  act=["If there is no matching pull request, revert from Git and raise a security incident."],
  esc="Reviewed the same day by the security on-call.")

a(layer=L, group="posture", name="KmsKeyRotationOverdue", sev="warning", team=S, svc="kms", comp="kms", dash="edge",
  expr="max by (key_alias) (kms_key_rotation_overdue_seconds) > 0", f="30m",
  sum="A KMS key is past its rotation date",
  series=[('kms_key_rotation_overdue_seconds{key_alias="locker-pan"}', "3600x{n}", "0x{n}")],
  failure="KMS key rotation overdue", impact="a cryptoperiod is exceeded; PCI DSS 3.7.4",
  sym="The rotation of a KMS key did not happen on schedule.",
  diag=["Check whether automatic rotation is enabled on the key and the key policy allows it."],
  act=["Enable rotation through Terraform or rotate the data key through the locker rotation job."],
  esc="Ticket to security; escalate to the compliance owner after 7 days.")

a(layer=L, group="posture", name="KyvernoAuditViolations", sev="warning", team=S, svc="kyverno", comp="kyverno", dash="edge",
  expr='sum by (policy_name) (increase(kyverno_policy_results_total{rule_result="fail",policy_validation_mode="audit"}[1h])) > 0', f="10m",
  sum="Kyverno audit policies report violations",
  series=[('kyverno_policy_results_total{rule_result="fail",policy_validation_mode="audit",policy_name="disallow-privileged"}', "0+1x{n}", "0+0x{n}")], labels={"policy_name": "disallow-privileged"},
  failure="Kyverno audit violations", impact="workloads break a rule that is not yet enforced; they will be blocked when it is",
  sym="A policy in audit mode reports failing resources.",
  diag=["List the failing resources per policy from the Kyverno policy report."],
  act=["Fix the manifests through pull requests before the policy moves to enforce."],
  esc="Ticket to the owner of the workload.")

gap(L, "unauthorized-api-calls", "cloudtrail", "Spike of AccessDenied API calls", "probing of permissions by a compromised principal", "security", "CloudTrail metric filter is not created yet")
