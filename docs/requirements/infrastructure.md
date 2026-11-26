---
status: baseline
---

# Infrastructure requirements

AWS accounts and network, cells, availability zones, the recovery regions, Kubernetes, Helm and the `deploy/` layout. Numbers are in `nfr.md`; the region model is ADR-0017.

## Accounts and network

| ID | Requirement | Verification | Implementation | Source |
|---|---|---|---|---|
| FR-INF-1 | AWS accounts shall be requested as code through Account Factory for Terraform, with the CDE accounts in the `Workloads/CDE` OU, and CDE workloads shall run only on the tainted On-Demand `cde` node pool of each cluster. | test | `infra/aft-account-requests/accounts/{infrastructure,workloads-cde,sandbox}.yaml` with `infra/aft-account-requests/tests`; `cde` pool of `infra/modules/karpenter`. | Section 3 (Landing Zone), ADR-001 |
| FR-INF-2 | Every environment and region shall own one non-overlapping /16 VPC with public, private and data tiers over three AZs, and the private tier shall reach the internet only through the egress path. | test | `infra/modules/vpc` (tiers per AZ, locked default security group, no internet gateway by default); CIDRs in `config/platform.yaml` `network`; `infra/modules/vpc/tests/vpc.tftest.hcl`. | Section 3 (network) |
| FR-INF-3 | AWS API traffic from the VPCs shall use VPC endpoints: gateway endpoints for S3 and DynamoDB, interface endpoints for ECR, STS, KMS, Secrets Manager, SSM and logs. | test | Endpoints of `infra/modules/vpc`, asserted in `infra/modules/vpc/tests`. | Section 3 (network), D4 |
| FR-INF-4 | Egress to PSPs shall leave through AWS Network Firewall that drops every destination except the PSP domains, through static Elastic IPs per AZ registered with every PSP. | test | `infra/modules/network-firewall` (strict-order policy on TLS SNI and HTTP host, `egress_public_ips` with `prevent_destroy`); `tests/`. | Section 3 (network), section 23.8, ADR-012 |
| FR-INF-5 | VPCs shall be connected through a transit gateway whose attachments each associate with one named route table, with blackhole routes between the CDE and platform tables. | test | `infra/modules/transit-gateway` (default association and propagation off, `static_routes`); `tests/`. | Section 3 (network) |
| FR-INF-6 | Each region that runs workloads shall have its own egress VPC, Network Firewall and transit gateway, so PSP traffic never crosses regions. | inspection | `infra/live/<env>/{eu-central-1,us-east-1}/{egress-vpc,firewall,tgw}`; `egress_cidrs` in `infra/live/<env>/env.hcl`. | ADR-0017 |
| FR-INF-7 | VPC flow logs shall be written to the central log archive in parquet. | test | `flow_logs_bucket_arn` of `infra/modules/vpc`; `infra/modules/log-archive` (Object Lock 365 days). | Section 3 (network), section 6 |

## Cells and availability zones

| ID | Requirement | Verification | Implementation | Source |
|---|---|---|---|---|
| FR-INF-8 | The working region shall run four working cells and one spare cell, each with its own EKS cluster, MemoryDB and Aurora, and one locker Aurora shared by all cells. | inspection | `infra/live/<env>/eu-central-1/{cell-0..cell-3,spare}/{eks,karpenter,memorydb,aurora,data-access,iam-workloads}` and `locker/`; `cells` in `env.hcl`. | Section 2 (cells), ADR-013, ADR-013a, section 1 |
| FR-INF-9 | Merchants shall be mapped to cells by the DynamoDB merchant-to-cell map, and a merchant shall be moved between cells by an audited script. | test | `infra/modules/dynamodb-global` (map table); `scripts/cells/migrate-merchant.py` with `scripts/cells/tests`. | Section 2 (cells), section 21.1 |
| FR-INF-10 | A hot merchant shall be isolated by raising the spare cell to the prod profile and moving the merchant there, with per-merchant rate limits at the edge. | test | `scripts/cells/migrate-merchant.py`; alerts `MerchantShareOfCellHigh` (above 30% of a cell) and `RateLimitHitsMerchant`; `deploy/platform/ratelimit`. | Section 21.1 (ADR-016) |
| FR-INF-11 | Inside the working region availability shall come from three AZs: Aurora writer of each cell in its own AZ with readers, MemoryDB multi-AZ, MSK replication factor 3 and pods spread per AZ with PDBs. | test | `writer_az` of `infra/modules/aurora-global`; MemoryDB 2 shards x 3 nodes; MSK `min.insync.replicas=2`; Kyverno `require-pdb`; `tests/contracts/test_platform_ha.py`; FIS `az-loss.json`. | D6, section 4 |

## Region model

| ID | Requirement | Verification | Implementation | Source |
|---|---|---|---|---|
| FR-INF-12 | eu-central-1 shall be the only region that accepts writes; there shall be no active-active operation. | test | `region_role = working` only in `infra/live/<env>/eu-central-1`; SCP `policy/scp/deny-dynamodb-writes-recovery-regions.json`; Global Accelerator validation rejects two active endpoint groups. | D6, ADR-0017 |
| FR-INF-13 | us-east-1 shall run a warm standby in environments with `standby.enabled`: per cell EKS, Karpenter node pools, MemoryDB and Aurora readers on the local secondary clusters, serving no requests while Frankfurt is healthy. | inspection | `infra/live/<env>/us-east-1/{cell-0..cell-3,spare,locker}`; `standby` in `config/environments/prod.yaml` (1 reader `db.r7g.4xlarge`, capped node pools); `recovery_instance_count` of `aurora-global`. | ADR-0017 |
| FR-INF-14 | us-east-2 shall hold only non-compute resources: VPC, KMS replica keys, ECR replicas, headless Aurora secondaries, DynamoDB, S3 and Secrets Manager replicas and backup vaults. | inspection | `infra/live/<env>/us-east-2/{vpc,kms,ecr,restore-test}` and `{cell-*,spare,locker}/{aurora,data-access}` without instances. | D6, D7, ADR-0017 |
| FR-INF-15 | The public API name shall resolve to Frankfurt while its HTTPS health check passes and to the us-east-1 standby only when it fails; the standby shall be health-checked too. | test | Route 53 failover records of `infra/modules/dns-routing` (`/health/deep` checks), stack `edge-dns-routing`; `infra/modules/dns-routing/tests/dns-routing.tftest.hcl`. | ADR-0017 |
| FR-INF-16 | Compute in us-east-2 (plan B) shall be created only from the Terraform and Terragrunt code of the cells, with node pools allowing several instance families and both architectures. | test | `_envcommon/compute/{eks,karpenter}.hcl`; `instance_families` of `infra/modules/karpenter` (m7g, m6g, m7i, m6i; r7g, r6g, r7i, r6i; arm64 and amd64); `tests/chaos/region-switch/plan-b.json`. | D7, ADR-009 |
| FR-INF-17 | The Aurora promotion shall happen in exactly one region under a lock per cell, and the replicas of the other region shall then follow the new writer. | test | DynamoDB lock record per cell and one concurrent run in `infra/modules/dr-failover`; `scripts/dr/failover.py` exit code 3 on a held lock; `scripts/dr/tests/test_failover.py`. | D7 |
| FR-INF-18 | Global Accelerator shall keep the recovery-region endpoint groups at weight 0 and traffic dial 0, and only one group shall be active. | test | `infra/modules/global-accelerator` (writing region weight 128, dial 100; validation on two active groups); its `tests/`. | Section 3, ADR-007 |
| FR-INF-19 | Recovery regions shall be prepared in advance with KMS multi-Region replica keys, IAM roles, Secrets Manager replicas, ECR replicas, firewall policy and data-store security groups that admit no client before the switch. | test | `infra/modules/{kms,secrets-replica,ecr,network-firewall}`; `infra/modules/data-access` with empty client lists in recovery regions; module `tests/`. | D7 |

## Kubernetes

| ID | Requirement | Verification | Implementation | Source |
|---|---|---|---|---|
| FR-INF-20 | EKS clusters shall have a private endpoint only, envelope encryption of Secrets with a customer managed key, access entries without creator admin and all five control-plane log types. | test | `infra/modules/eks`; `infra/modules/eks/tests/eks.tftest.hcl`. | Section 4 (clusters), ADR-008 |
| FR-INF-21 | Nodes shall be provisioned by Karpenter on pinned Bottlerocket with IMDSv2 hop limit 1, encrypted gp3 and no public IP, in pools `payments`, `stateful`, `cde` and `workers`. | test | EC2NodeClass and NodePools in the `manifests` output of `infra/modules/karpenter`; `tests/`; alert `NodeImageStale` (node image older than 30 days). | Section 26.1, section 26.4, section 26.6 |
| FR-INF-22 | The `cde` node pool shall be On-Demand and tainted in every environment so that only CDE workloads run on it; Spot is allowed only in pools listed in `spot_pools`. | test | `cde` pool On-Demand and tainted in `infra/modules/karpenter`; `spot_pools` in `config/environments/*.yaml` never contains `cde`. | Section 26.2 |
| FR-INF-23 | Pods shall receive AWS access only through EKS Pod Identity roles of their cell with the workload permissions boundary and named resources. | test | `infra/modules/iam-workloads` (trust on `pods.eks.amazonaws.com`, cluster ARN condition, no `*` except the metric-read policy); its `tests/`. | Section 26.3, section 23.2 |
| FR-INF-24 | Analytics (MSK, OpenSearch, ClickHouse) shall run outside the CDE on its own cluster in the working region. | inspection | `infra/live/<env>/eu-central-1/analytics/{eks,karpenter,msk,opensearch,clickhouse}`. | Section 2, ADR-011 |

## Helm and the deploy layout

| ID | Requirement | Verification | Implementation | Source |
|---|---|---|---|---|
| FR-INF-25 | Every Kubernetes manifest shall live under `deploy/`: service charts in `deploy/charts/`, environment values in `deploy/envs/`, platform addons in `deploy/platform/`, Argo CD in `deploy/argocd/`. | test | `tools/lint/structure`; Kyverno `disallow-ingress`; Argo CD ApplicationSets in `deploy/argocd/templates/`. | Section 17 |
| FR-INF-26 | A chart shall keep one file per resource kind in `templates/`, unit tests in `tests/`, `values.schema.json` and `values.yaml` next to `Chart.yaml`, and lint values in `ci/lint-values.yaml`. | test | Layout of `deploy/charts/<chart>/` checked by `make lint-helm test-helm` (`helm lint --strict`, `helm unittest`, kubeconform). | Section 17 |
| FR-INF-27 | Environment values shall exist only under `deploy/envs/<env>/[<region>/[<cell>/]]values.yaml`, and addons only under `deploy/platform/`. | inspection | `deploy/envs/{dev,stage,prod}/<region>/<cell>/values.yaml`; `deploy/envs/prod/us-east-1/` for the standby cells. | Section 17 |
| FR-INF-28 | Service charts shall be consumed by the per-cell umbrella charts `payments-cell`, `payments-locker` and `payments-edge`, with shared templates from the `platform-common` library chart. | test | `deploy/charts/{payments-cell,payments-locker,payments-edge}/Chart.yaml` dependencies; `deploy/charts/platform-common/templates/`; chart `tests/`. | Section 17 |
| FR-INF-29 | Entry points shall use the Gateway API (Istio), never the Ingress resource. | test | `deploy/platform/gateway-api-crds`, `deploy/platform/admin-gateway/manifests/gateway.yaml`; Kyverno `policy/kyverno/disallow-ingress` with `kyverno test`. | Section 4, owner decision |

## DNS and certificates

| ID | Requirement | Verification | Implementation | Source |
|---|---|---|---|---|
| FR-INF-30 | Public zones shall carry CAA records limited to ACM and Let's Encrypt and EC P-256 ACM certificates validated by DNS. | test | `infra/modules/dns-certs` (optional DNSSEC with a KMS key-signing key); its `tests/`. | Section 20.8 |
| FR-INF-31 | Certificate expiry shall alert at 14 days for every probed endpoint and at 30 days for PSP mTLS certificates. | test | Alerts `CertificateExpiryCritical` and `PspMtlsCertExpiring30d` in `observability/alerts/network/certificates.yaml`; cert-manager in `deploy/platform/cert-manager`. | Section 20.8 |
