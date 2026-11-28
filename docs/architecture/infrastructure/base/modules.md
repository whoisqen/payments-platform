# Module catalogue

Every directory in `infra/modules/` is one Terraform module with `versions.tf`, `variables.tf`, `main.tf`, `outputs.tf`, a short README and `tests/` (mock providers, no credentials). The README of each module is the reference for its inputs; this table is the index. "Used by" lists the live units under `infra/live/`, where `<env>` is dev, stage or prod.

| Module | Purpose | Key resources | Used by |
|---|---|---|---|
| `admin-edge` | Private entry to the admin tools | Private Route 53 zone, wildcard alias to the internal NLB, AWS Private CA root, Pod Identity roles for the Load Balancer Controller and the Private CA issuer | `shared-services/eu-central-1/admin-edge` |
| `argocd-access` | IAM side of Argo CD across accounts | Hub roles in shared-services (controller, registration), spoke role `<prefix>-<env>-argocd-controller` per environment | `shared-services/eu-central-1/argocd-access`, `<env>/eu-central-1/argocd-access` |
| `argocd-registration` | Registration of one cluster with Argo CD | Secret `<prefix>/argocd/clusters/<name>` in shared-services | `<env>/<region>/<cluster>/argocd-registration`, next to every `eks` unit |
| `argocd-standby` | Argo CD core in us-east-1 when eu-central-1 is gone | IRSA role on the first standby cell cluster, access entries on every standby cluster | `prod/us-east-1/argocd-standby` |
| `admin-agent-env` | Read access of the admin AI agent to one environment | Read-only role `<prefix>-<env>-admin-agent`, assumed by the Bedrock role of shared-services for each run; writes, secrets and keys denied | `<env>/eu-central-1/admin-agent` |
| `aurora-global` | Aurora PostgreSQL 16 global cluster of a cell or the locker | Global cluster, writer and readers, the us-east-1 secondary with its standby instance, RDS Proxy and its logins, parameter groups, lag alarm | `<env>/<region>/<cell or locker>/aurora` |
| `aurora-schedule` | Stop and start dev Aurora outside working hours | EventBridge Scheduler schedules, scoped role | `dev/eu-central-1/aurora-schedule` |
| `backup` | AWS Backup by tier | Vaults (with Vault Lock), plans gold, silver, bronze, copy actions, restore testing plan | `<env>/eu-central-1/backup` |
| `bedrock-access` | Bedrock for the CI review and the admin AI agent | OIDC review role, admin-agent role, guardrail, `bedrock-runtime` endpoint, budget and token alarms | `shared-services/eu-central-1/bedrock-access` |
| `cell-endpoint` | Entry of one cell from the edge cluster | Internal NLB, security groups, private zone `<cell>.<cluster_domain>`, record `router.payments.svc.<cell>.<cluster_domain>`, load balancer controller role | `<env>/<region>/<cell>/endpoint` |
| `cell-migration` | Merchant moves between cells | SSM Automation documents `cell-copy-merchant`, `cell-verify-merchant`, automation role | `<env>/eu-central-1/cell-migration` |
| `central-secrets` | Admin tool secrets in shared-services | 15 Secrets Manager containers, External Secrets role with Pod Identity | `shared-services/eu-central-1/central-secrets` |
| `ci-oidc-roles` | Terraform plan and apply roles for GitHub | GitHub OIDC provider, `pay-<env>-glob-tf-plan`, `pay-<env>-glob-tf-apply-<component>`, optional ECR read role | `<env>/eu-central-1/ci-oidc-roles`, `shared-services/eu-central-1/ci-oidc-roles` |
| `ci-runners` | Self-hosted GitHub runners on EC2 Spot | Launch templates, Auto Scaling groups, schedules, cache bucket, GitHub App secrets, ECR push role | `shared-services/eu-central-1/ci-runners` |
| `clickhouse` | AWS side of ClickHouse on EKS | Pod Identity role, backup settings, backup and restore alarms | `<env>/eu-central-1/analytics/clickhouse` |
| `data-access` | Network access to the data stores of one cell | Security groups per store, Aurora DB subnet group | `<env>/<region>/<cell or locker>/data-access`, `<env>/eu-central-1/analytics/msk-access` |
| `dns-certs` | Public zone and certificates | Route 53 zone, CAA records, optional DNSSEC, ACM certificates with DNS validation | `<env>/eu-central-1/edge-dns` |
| `dns-routing` | Failover of the public API name | Failover CNAME records, HTTPS health checks | `prod/eu-central-1/edge-dns-routing` |
| `dr-failover` | Automatic promotion of the standby region | CloudWatch alarm, SNS topic with KMS key, Lambda, DynamoDB lock table | `prod/us-east-1/dr-failover` |
| `dynamodb-global` | Merchant-to-cell map | Global table with MREC replicas, PITR, `deny_recovery_writes` IAM policy | `<env>/eu-central-1/dynamodb` |
| `ecr` | Container registry | Repositories, lifecycle, registry scanning, replication, creation templates, pull-through cache rules | `<env>/<region>/ecr`, `shared-services/eu-central-1/ecr` |
| `egress-routing` | Firewall on the only egress path | Routes of the egress VPC: attachment subnets to the firewall endpoint, firewall subnets to the NAT gateway, per AZ | `<env>/<region>/egress-routing`, `shared-services/eu-central-1/egress-routing` |
| `eks` | EKS cluster | Cluster with private endpoint, access entries, OIDC provider, managed add-ons, bootstrap node group, control-plane log export | `<env>/<region>/<cluster>/eks` for cells, `locker`, `edge`, `control-center`, `analytics`; `shared-services/eu-central-1/central/eks` |
| `fis-experiments` | Chaos experiment templates | AWS FIS templates, SSM Automation document, log group | `{stage,prod}/eu-central-1/fis-experiments` |
| `fis-prereqs` | What the FIS templates need | Permissions boundary, composite stop alarm, MSK reboot document | `{stage,prod}/eu-central-1/fis-prereqs` |
| `global-accelerator` | Static anycast IPs for the API | Accelerator, TCP 443 listener, endpoint group per region | `<env>/eu-central-1/edge-accelerator` |
| `iam-workloads` | Workload roles of one cluster | Pod Identity roles for router, locker, drainer, scheduler, external-secrets and `yace` | `<env>/<region>/<cluster>/iam-workloads` for cells, `locker`, `edge`, `control-center` |
| `identity-center` | Human access to AWS | Permission sets, standing assignments, JIT CDE grants | `management/eu-central-1/identity-center` |
| `jit-revocation-schedule` | Removal of expired CDE grants | EventBridge schedule that starts `cde-jit-revocation.yml` through an API destination | `management/eu-central-1/jit-revocation` |
| `karpenter` | AWS side of Karpenter and its manifests | Controller and node roles, access entry, SQS interruption queue, EventBridge rules; EC2NodeClass and NodePools as output | `<env>/<region>/<cluster>/karpenter`, `shared-services/eu-central-1/central/karpenter` |
| `kms` | One customer managed key | Key (multi-Region primary or replica), alias, key policy | called by `kms-set` |
| `kms-set` | Every key of a region | Calls `kms` once per purpose | `<env>/<region>/kms`, `shared-services/<region>/kms` |
| `locker-endpoint` | Path from the cells to the locker | Internal NLB, security group, private zone `locker.<cluster_domain>`, alias `locker.payments.svc.locker.<cluster_domain>` | `<env>/<region>/locker/endpoint` |
| `log-archive` | Immutable organization log bucket | S3 bucket with Object Lock COMPLIANCE, KMS key, access log bucket | `security/eu-central-1/log-archive` |
| `log-ingestion` | Writers of the central log domain | Logstash IRSA role, exporter and Grafana roles, OpenSearch Ingestion pipelines for the audit trail | `shared-services/eu-central-1/logs/ingestion` |
| `logs-edge` | Entry of the central logs | Logstash TLS certificate from the private CA, its secret, private name of the log intake | `shared-services/eu-central-1/logs/edge` |
| `memorydb` | Hot state of one cell | MemoryDB cluster, ACL, IAM and password users, parameter group | `<env>/<region>/<cell>/memorydb` |
| `msk` | Event stream | MSK cluster, configuration, S3 sink role, producer policy, log group | `<env>/eu-central-1/analytics/msk` |
| `network-firewall` | Egress control | Network Firewall, fence and allowlist rule groups, policy, NAT gateways, Elastic IPs, logging | `<env>/<region>/firewall` |
| `observability-storage` | Buckets of the central stack | S3 buckets `tempo`, `sentry`, `vmbackup`, one Pod Identity role per bucket, `yace` role | `shared-services/eu-central-1/observability-storage` |
| `okta-sso` | Okta sign-in to the admin tools | Okta groups, OIDC applications, sign-in policy, client secrets in Secrets Manager | `shared-services/eu-central-1/okta-sso` |
| `opensearch` | Central log domain | OpenSearch domain `pay-shared-euc1-logs`: dedicated masters, hot nodes over three AZs, UltraWarm, VPC only, fine-grained access control | `shared-services/eu-central-1/logs/opensearch` |
| `opensearch-endpoint` | Log domain inside one environment | OpenSearch-managed VPC endpoint, security group | `<env>/eu-central-1/logs-endpoint` |
| `opensearch-indices` | Layout of the log domain | Data streams `logs-app-<env>`, `logs-audit`, ISM policies, roles and mappings | `shared-services/eu-central-1/logs/opensearch-indices` |
| `org-config` | AWS Config for the organization | Delegation, aggregator, recorder StackSet, conformance pack | `management/eu-central-1/org-config`, `security/eu-central-1/org-config` |
| `org-policies` | Organization policies | SCPs, tag policies, backup policies, RCP, attachments | `management/eu-central-1/org-policies` |
| `org-security-services` | Organization security services | Delegated administrators, GuardDuty, Security Hub, Inspector, Macie | `management/eu-central-1/org-security-services`, `security/eu-central-1/org-security-services` |
| `org-trail` | Organization CloudTrail | Trail, CloudWatch log group, KMS key | `management/eu-central-1/org-trail` |
| `panel-edge` | Public browser entries | CloudFront distributions with VPC origin, ACM certificates, cache, origin and response header policies, aliases, logging | `<env>/us-east-1/panel-edge` |
| `permissions-boundary` | Cap on every role of an account | IAM policy `workload-boundary` | `<env>/eu-central-1/permissions-boundary` |
| `restore-automation` | Daily restore test evaluation | SSM Automation document, EventBridge trigger, metrics | `prod/us-east-1/restore-test` |
| `runbook-roles` | Roles of the runbook workflows | `<prefix>-<env>-glob-runbook-diagnose`, `<prefix>-<env>-glob-runbook-actions` | `<env>/eu-central-1/runbook-roles` |
| `s3-backup` | Locked, replicated buckets | S3 buckets with Object Lock, RTC replication, lifecycle, latency alarm | `<env>/eu-central-1/{s3-backup,s3-event-archive}`, `shared-services/eu-central-1/vault-snapshots` |
| `secrets-replica` | Replicated secret containers | Secrets Manager secrets with replicas in us-east-1 (prod) | `<env>/eu-central-1/secrets` |
| `sentry-alerts` | Sentry issue alerts | Rules `critical` and `high` on every project, posting to Slack | `shared-services/eu-central-1/sentry` |
| `tf-exec-role` | Role every generated provider assumes | `<prefix>-<root>-tf-exec`, trusted by the plan and apply roles of shared-services | `<root>/eu-central-1/tf-exec`, `security/eu-central-1/tf-exec-log-archive` |
| `transit-gateway` | Hub of the egress path | Transit gateway, route tables, attachments, static routes, RAM share | `<env>/<region>/tgw` |
| `vault-platform` | AWS side of Vault | Unseal KMS key, Pod Identity roles for server, snapshot and bootstrap | `shared-services/eu-central-1/vault` |
| `vpc` | Three-AZ VPC | VPC, public, private and data subnets, route tables, endpoints, flow logs | `<env>/<region>/vpc`, `<env>/<region>/egress-vpc`, `shared-services/eu-central-1/vpc` |
| `waf-edge` | WAF for the browser entries | WAFv2 web ACLs, managed groups, rate rules, log groups | `<env>/us-east-1/waf-edge` |

## Stacks outside `infra/live`

| Stack | Purpose |
|---|---|
| `infra/bootstrap` | State bucket, state KMS key, replicas, first plan and apply roles; applied once with local state |
| `infra/aft-account-requests` | Account requests per OU for Account Factory for Terraform |
| `infra/github` | Repository, rulesets, environments and CODEOWNERS as code; modules `organization`, `repository`, `rulesets`, `environments`, `codeowners` |

## Adding a module

1. Create `infra/modules/<name>/` with `versions.tf`, `variables.tf`, `main.tf`, `outputs.tf`, a README of at most 10 lines and `tests/` with `mock_provider "aws"`.
2. Require the five tags that the path cannot fill (`team`, `owner`, `pci-scope`, `data-class`, `backup-tier`) through a `tags` variable.
3. Run `terraform init -backend=false && terraform fmt -check && terraform validate && terraform test`, then `tflint`.
4. Add an `_envcommon` file and the live units; add a row to this table.
