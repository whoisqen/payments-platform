# Security controls

This page lists the controls of the platform, grouped by what they protect, and points to where each one lives. The [threat model](threat-model.md) explains which threats they answer and what risk remains.

## Card data and PCI DSS scope

- **Only the locker holds a PAN.** Every other component sees a token. The locker encrypts each record with keys protected by its own KMS key, which only the locker role may use. CVV is never stored.
- **Small CDE.** Router, locker, drainer, scheduler and their stores make up the CDE; every resource carries a `pci-scope` tag. The organization layout gives the CDE its own OU (`Workloads/CDE`) with a resource control policy. Analytics runs on its own cluster, and the control center, CI and monitoring sit outside the CDE.
- **Isolation inside a cluster.** CDE workloads run on their own tainted On-Demand node pool, the locker pods have their own pod security group, NetworkPolicies deny by default, and Istio requires mTLS (PeerAuthentication STRICT). The locker accepts only the router identity.
- **No card data in telemetry.** `Secret<T>` in Rust code, Semgrep rule `no-pan-logging`, the OpenTelemetry collector in each cluster deletes and masks card fields before data leaves, the central Logstash masks PAN-like numbers again before OpenSearch, Sentry scrubs on three layers, and Macie scans the S3 buckets of the CDE accounts every day.
- **Evidence.** AWS Config runs the PCI DSS v4 conformance pack in every account; Security Hub runs PCI DSS v4.0.1, AWS FSBP and CIS v3.0.0.

## Zero trust

- No network location is trusted by itself. Inside the mesh every call is mTLS with a SPIFFE identity and an AuthorizationPolicy names who may call whom.
- Every workload has its own Pod Identity role per cell, under a permissions boundary, naming its resources; policies with `*` actions or resources fail the OPA check `iam-no-wildcard`.
- Data stores admit connections only from the node security groups of the clusters that use them; Aurora admits only its RDS Proxy.
- Admin tools are reachable only on a private DNS zone inside the platform VPCs, and every sign-in goes through Okta with two factors.

## Identity and access

| Who | How | Limit |
|---|---|---|
| People in AWS | IAM Identity Center, Okta as IdP (SAML, MFA), groups pushed by SCIM | `Admin` only in management; `SRE-View` read-only everywhere; `SRE-CDE` never standing |
| CDE access | Just-in-time grant by pull request to `config/access/cde-jit-grants.yaml`, approved by a second SRE | at most 1 hour; a job every 15 minutes revokes expired grants |
| People in clusters | EKS access entry `AmazonEKSViewPolicy` | view only |
| Admin tools | Okta OIDC per tool; Grafana organizations per group | administrators re-authenticate every 2 hours |
| Argo CD | access entry scoped to the platform namespaces | never cluster-admin |
| CI | GitHub OIDC: plan role read-only, apply role per component trusting only `main` and `release/*` | 1 hour, permissions boundary |
| Region-switch fallback (the one cluster-admin exception) | `pay-prod-glob-dr-apply`, trusted only by the GitHub environment `dr-compute-prod` with required reviewers; it gets cluster-admin on `pay-prod-use1-eks-cell-0` only while `argocd-standby` is applied with `PAY_ARGOCD_INSTALL=true`, to install Argo CD core when the central Argo CD in Frankfurt is unreachable | removed by the next apply without the flag; the hot standby normally needs none of it |
| Merchants | API keys stored as hashes | rate limited per merchant |

Quarterly access review (PCI DSS 7.2.4) reads the standing assignments output of `infra/modules/identity-center`.

## Organization guardrails (SCPs and RCP)

From `policy/scp/`: allowed regions only; CloudTrail, Config and GuardDuty cannot be stopped or changed outside the security pipeline; IMDSv2 with hop limit 1; no IAM users or access keys; no public S3 ACLs or block changes; protected tags editable only by automation; no DynamoDB writes in recovery regions except replication. A resource control policy keeps S3, KMS and Secrets Manager of the CDE OU closed to principals outside the organization. `bedrock-access` outputs an SCP document that keeps Bedrock calls in EU regions.

## Secrets and keys

- No secret in Git. Vault (KV v2) and AWS Secrets Manager hold them; External Secrets Operator delivers them; Terraform creates secret shells without values.
- Customer managed KMS keys per purpose and cell, yearly rotation, multi-Region replicas in us-east-1 for prod.
- gitleaks scans the full Git history in CI and locally with `make lint-secrets`.
- Vault: auto-unseal with KMS, root token revoked after bootstrap, audit device on, break-glass procedure in `deploy/platform/vault/README.md`.

## Supply chain and scanning

- Images by digest only, signed with cosign, SBOM attached; Kyverno admits only signed images from the platform registry.
- Distroless images; OPA rules on Dockerfiles.
- Scans in CI: Semgrep, CodeQL, Checkov, Trivy (config, filesystem, image), cargo-deny, dependency review, license policy, zizmor, OpenSSF Scorecard, OWASP ZAP baseline against stage. Details in [CI/CD](../architecture/delivery/cicd-security.md).
- Inspector scans EC2, ECR and Lambda continuously.

## Detection and incident response

- GuardDuty in every account with S3, EKS audit logs, EBS malware protection, RDS login events, Lambda network logs and EKS Runtime Monitoring.
- Organization CloudTrail and Config to the log-archive bucket under Object Lock (compliance mode, 365 days). OpenSearch Ingestion copies CloudTrail and EKS audit into `logs-audit` of the central log domain for search (365 days); members of the Okta security group read it in OpenSearch Dashboards ([logging](../architecture/runtime/logging.md)).
- Security alerts in `observability/alerts/security-pci/` go to the security channel. Each has a runbook in `docs/runbooks/security-pci/`: root account login, break-glass role used, IAM change outside Terraform, SCP changed, GuardDuty high and CDE runtime findings, PAN found in logs, Vault sealed, Vault audit device failing.
- Response: the on-call engineer acknowledges, follows the runbook and adds the incident commander. Evidence stays in the locked log archive. A postmortem goes to `docs/postmortems/`.

## Where in the repo

| Path | What |
|---|---|
| `policy/` | SCPs, OPA, Kyverno, Semgrep, Config pack, tagging, scanner thresholds |
| `infra/modules/org-*`, `log-archive`, `identity-center`, `okta-sso` | Organization security |
| `infra/modules/iam-workloads`, `kms`, `kms-set`, `vault-platform` | Workload identity and keys |
| `deploy/platform/vault`, `external-secrets`, `kyverno`, `istio` | In-cluster controls |
| `observability/alerts/security-pci/`, `docs/runbooks/security-pci/` | Detection and response |
| `SECURITY.md` | Reporting a vulnerability |
