---
status: baseline
---

# Security and access requirements

Platform security controls, access to AWS and admin tools, zero trust and break-glass. Business behavior of the payment services is out of scope (`srs.md` section 1).

## Card data and encryption

| ID | Requirement | Verification | Implementation | Source |
|---|---|---|---|---|
| FR-SEC-1 | Card data (PAN, CVV) shall never appear in logs, traces, metric labels or fixtures. | test | Semgrep `policy/semgrep/no-pan-logging.yaml` with its test file `no-pan-logging.rs`; alert `PanDetectedInLogs`; Macie in `infra/modules/org-security-services`. | Section 6 (card data) |
| FR-SEC-2 | Every data store, log group, bucket, secret and EBS volume shall be encrypted with a customer managed KMS key rotated yearly, with multi-Region replicas in the recovery regions. | test | OPA `policy/opa/terraform/kms-cmk-required`; `infra/modules/kms` (`multi_region`, `is_replica`) and its `tests/`; alert `KmsKeyRotationOverdue`. | Section 6, section 13 (ADR-013b) |
| FR-SEC-3 | Traffic between services shall use mTLS of the Istio mesh, and data-store connections shall require TLS. | test | `tls` of `platform-common` `_destinationrule.tpl`; `rds.force_ssl` and TLS 1.3 in `infra/modules/aurora-global`; TLS in transit of `memorydb`, `msk`, `opensearch`. | Section 6 (encryption in transit), ADR-005 |
| FR-SEC-4 | CDE resources shall never be public, and CDE S3, KMS and Secrets Manager shall deny principals outside the organization. | test | OPA `policy/opa/terraform/cde-no-public`; resource control policy on the CDE OU in `infra/modules/org-policies`; SCP Sids `DenyPublicS3AccessBlockChanges`, `DenyPublicS3Acls`. | Section 6, section 3 |

## Identity and access

| ID | Requirement | Verification | Implementation | Source |
|---|---|---|---|---|
| FR-SEC-5 | People shall reach AWS only through IAM Identity Center with Okta SAML sign-in, MFA and SCIM groups; IAM users and access keys shall be denied. | test | `infra/modules/identity-center` and its `tests/`; SCP Sid `DenyIamUsersAndAccessKeys` in `policy/scp/security-baseline.json`, tested by `policy/scp/tests/test_scp.py`. | Section 6 (identity), section 23.1 |
| FR-SEC-6 | CDE access shall be just-in-time only: a grant of at most 1 hour added by pull request, approved by a second SRE and revoked by a job every 15 minutes; no standing CDE access shall exist. | test | `cde_jit_grants` with expiry precondition and the validation that rejects standing `SRE-CDE` in `infra/modules/identity-center` and its `tests/`; scheduled revocation run every 15 min. | Section 23.1, section 23.2 |
| FR-SEC-7 | Use of the break-glass role shall notify the security channel at once and be matched with the incident number of its request. | test | Alert `BreakGlassRoleUsed` (`security_events_total{event="break_glass"}`) with test in `observability/tests/security-pci/`; runbook `docs/runbooks/security-pci/break-glass-role-used.md`. | Section 14 (zero manual actions), section 23 |
| FR-SEC-8 | IAM changes outside Terraform, SCP changes and root logins shall each raise a security alert. | test | Alerts `IamChangeOutsideTerraform`, `ScpChanged`, `RootAccountLogin` in `observability/alerts/security-pci/detection.yaml`; organization trail `infra/modules/org-trail`. | Section 23.9 |
| FR-SEC-9 | IAM policies shall name actions and resources without wildcards, and every workload or automation role shall carry the permissions boundary. | test | OPA `policy/opa/terraform/iam-no-wildcard`; boundary and named resources in `infra/modules/iam-workloads` and `infra/modules/ci-oidc-roles`; module `tests/`. | Section 23.2 |
| FR-SEC-10 | Database access shall be code: each data store admits only the security groups of its listed clients, Aurora only its RDS Proxy, and each service a named login. | test | `infra/modules/data-access`; `proxy_auth_entries` in `_envcommon/data/aurora.hcl`; `rds-db:connect` ARNs in `infra/modules/iam-workloads`. | Section 20.1 |

## Automation roles and CI

| ID | Requirement | Verification | Implementation | Source |
|---|---|---|---|---|
| FR-SEC-11 | CI shall reach AWS only through GitHub OIDC: plan roles from pull requests read-only, apply roles only from `main` and `release/*` with a 1 hour session and their own state prefix. | test | `infra/modules/ci-oidc-roles` (trust pinned to repository and ref) and its `tests/` with negative cases; OPA `policy/opa/github/id-token-aws-only`. | Section 23.3 |
| FR-SEC-12 | Workflows shall set `permissions: {}` at the top, grant permissions per job and pin every action by commit SHA. | test | OPA `policy/opa/github/permissions-at-job-level` and `no-untrusted-interpolation`; zizmor and `actionlint` in the `workflows` job of `.github/workflows/security.yml`. | Section 23.3, section 20.5 |
| FR-SEC-13 | Runners of untrusted pull requests shall have no AWS role, their own subnets and no route to cells or the CDE. | test | Untrusted pool of `infra/modules/ci-runners` and `infra/modules/ci-runners/tests/ci-runners.tftest.hcl`. | Section 23.3 |
| FR-SEC-14 | Argo CD shall be limited to the namespaces of its cluster's platform and services, never cluster-admin, and people shall have view-only cluster access. | test | `access_entries` of `infra/live/<env>/env.hcl` (namespace-scoped `argocd`, `sre-view` with `AmazonEKSViewPolicy`); `deploy/argocd/templates/appprojects.yaml`. | Section 23.4 |

## Kubernetes and supply chain

| ID | Requirement | Verification | Implementation | Source |
|---|---|---|---|---|
| FR-SEC-15 | Every image shall be referenced by digest, signed with cosign and pulled only from the platform registries; tag `latest` shall be rejected. | test | Kyverno `require-image-digest`, `require-signed-images`, `restrict-registries`, `disallow-latest-tag` with `kyverno test`; OPA `policy/opa/docker/{pinned-digest,no-latest-tag}`. | Section 20.5 |
| FR-SEC-16 | Images shall be distroless and carry an SBOM and provenance attestation. | test | OPA `policy/opa/docker/distroless`; SBOM and provenance in `.github/workflows/images.yml`. | Section 20.5 |
| FR-SEC-17 | `exec` into CDE pods shall be denied. | test | Kyverno `policy/kyverno/cde-no-exec`. | Section 6, section 23.4 |
| FR-SEC-18 | Namespaces shall default-deny network traffic and allow only explicit flows, and a change of a CDE network policy shall raise an alert. | test | `platform-common` `_networkpolicy.tpl` with chart tests; Vault `config` NetworkPolicies; alert `CdeNetworkPolicyChanged`. | Section 6 (perimeter), section 23.1 |
| FR-SEC-19 | Pull requests shall block on secrets, high or critical vulnerabilities with a fix, high or critical IaC findings, high zizmor findings, denied licenses and the repository Semgrep rules. | test | Jobs `secrets`, `dependencies`, `iac`, `workflows`, `licenses`, `semgrep` of `.github/workflows/security.yml`; thresholds in `policy/security/`; waiver checks in `tools/ci/tests/security`. | Section 6 (DevSecOps) |
| FR-SEC-20 | CodeQL shall scan every pull request, `main` and once a week; a DAST baseline shall run against the platform API. | test | `.github/workflows/codeql.yml`; job `dast` (ZAP baseline) of `.github/workflows/security.yml` with `policy/security/dast/`. | Section 6 (DevSecOps) |

## Detection and secrets

| ID | Requirement | Verification | Implementation | Source |
|---|---|---|---|---|
| FR-SEC-21 | GuardDuty (with Runtime Monitoring on EKS), Security Hub, Inspector and Macie shall be enabled for every account and region through a delegated administrator. | test | `infra/modules/org-security-services`; alerts `GuardDutyHighFinding`, `GuardDutyRuntimeCdeFinding`. | Section 6 (perimeter and detection) |
| FR-SEC-22 | CloudTrail, Config and GuardDuty shall not be disabled by any member account, and Config shall evaluate the PCI DSS v4 conformance pack in every account. | test | SCP `policy/scp/security-baseline.json`; `infra/modules/org-config` with `policy/config/pci-dss-pack/pci-dss-v4.yaml` and `pack-lint-test.rego`. | Section 20.4 |
| FR-SEC-23 | Audit logs shall be immutable for 365 days in the log-archive account. | test | `infra/modules/log-archive` (Object Lock COMPLIANCE 365 days, deletes denied) and `infra/modules/org-trail`; tests in both modules. | Section 6, section 20.4 |
| FR-SEC-24 | Secrets shall be kept in Vault or Secrets Manager, never in Git or Terraform state, and Secrets Manager secrets shall be replicated to both recovery regions. | test | `infra/modules/secrets-replica` (no secret version resource); External Secrets in `deploy/platform/external-secrets`; `gitleaks` in `make lint-secrets`. | Section 6 (secrets), section 23.6 |
| FR-SEC-25 | Vault shall run as 3 pods over three AZs with Raft storage, KMS auto-unseal and an hourly snapshot; sealing and audit device failures shall alert. | test | `deploy/platform/vault`; unseal key and roles of `infra/modules/vault-platform`; alerts `VaultSealed`, `VaultAuditDeviceFailing`. | Section 20.3 |
| FR-SEC-26 | SSH shall not exist on nodes; IMDSv2 with hop limit 1 shall be enforced by SCP for every instance. | test | Bottlerocket EC2NodeClass of `infra/modules/karpenter`; SCP Sids `RequireImdsV2WithHopLimitOne`, `DenyImdsHopLimitAboveOne`. | Section 26.1, section 26.5 |

## Admin interfaces and agents

| ID | Requirement | Verification | Implementation | Source |
|---|---|---|---|---|
| FR-SEC-27 | Admin tools (Argo CD, Vault, Grafana, Alertmanager, VictoriaMetrics, Prometheus, Sentry) shall be reachable only through the internal gateway in a private zone, behind Okta OIDC sign-in. | test | `infra/modules/admin-edge` (private zone, internal NLB); `deploy/platform/admin-gateway/manifests/` (oauth2-proxy); `infra/modules/okta-sso` with its `tests/`. | Section 16 |
| FR-SEC-28 | Admin roles shall come from six Okta groups mapped to tool roles; a person in none of them shall not sign in. | test | `groups` claim limited to six names in `infra/modules/okta-sso`; `access.grafana_groups` in `config/platform.yaml`; rendered by `tools/config/render/render_admin_sso.py`. | Section 16 |
| FR-SEC-29 | AI agents shall have read and analysis tools plus named runbook actions that run only after a human confirms, with no access to the CDE environment. | test | `config/admin-agent.yaml` (cde-prod excluded); Bedrock roles of `infra/modules/bedrock-access` with its `tests/`; budget at 80% and 100%. | Section 23.5 |

## Edge protection

| ID | Requirement | Verification | Implementation | Source |
|---|---|---|---|---|
| FR-SEC-30 | The organization shall subscribe to AWS Shield Advanced with automatic renewal for the public entry points. | test | `aws_shield_subscription` behind `shield_advanced_enabled` in `infra/modules/org-security-services`; `tests/org-security-services.tftest.hcl`. | Section 6 (perimeter), ADR-006 |
