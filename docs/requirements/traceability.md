---
status: baseline
---

# Traceability

Source sections to requirement IDs, ADRs to IDs, and each requirement to its verifying artefact. Generated from the requirement files; IDs are defined only in the files named in `README.md`.

## Source sections

| Section | Requirement IDs | Note |
|---|---|---|
| 1 Overview (components, regions) | FR-INF-8 |  |
| 1 Load | NFR-CAP-1, NFR-CAP-2, NFR-CAP-3, NFR-CAP-4, NFR-CAP-5 |  |
| 1 SLO | NFR-SLO-1, NFR-SLO-2, NFR-SLO-3, NFR-SLO-4 |  |
| 1 RTO / RPO | NFR-REC-1, NFR-REC-7, NFR-REC-9 |  |
| 2 Architecture (cells, write path, 7 calls, PSP, patterns, CAP and PACELC) | NFR-SLO-5, FR-INF-8, FR-INF-9, FR-INF-24, FR-DAT-1, FR-DAT-6, FR-DAT-10 |  |
| 3 AWS accounts, CDE, network, DR | FR-INF-1, FR-INF-2, FR-INF-3, FR-INF-4, FR-INF-5, FR-INF-7, FR-INF-18, FR-SEC-4, FR-POL-10 |  |
| 4 Kubernetes and delivery (clusters, GitOps, deployment strategies) | FR-INF-11, FR-INF-20, FR-INF-29, FR-DEL-9, FR-DEL-10, FR-POL-9 |  |
| 5 Data and backups (PostgreSQL, migrations, backups) | FR-DAT-2, FR-DAT-3, FR-DAT-4, FR-DAT-23 |  |
| 6 Security and PCI DSS (platform controls) | FR-INF-7, FR-DAT-13, FR-SEC-1, FR-SEC-2, FR-SEC-3, FR-SEC-4, FR-SEC-5, FR-SEC-17, FR-SEC-18, FR-SEC-19, FR-SEC-20, FR-SEC-21, FR-SEC-23, FR-SEC-24, FR-SEC-30, FR-POL-13 |  |
| 7 Observability and alerting | FR-OBS-1, FR-OBS-2, FR-OBS-3, FR-OBS-4, FR-OBS-17 |  |
| 8 Replicas and autoscaling | FR-OBS-18, FR-OBS-19, FR-OBS-20 |  |
| 8 Load tests | NFR-CAP-3, NFR-CAP-4, NFR-CAP-6, FR-OBS-21 |  |
| 8 Chaos engineering | FR-OBS-22, FR-OBS-23 |  |
| 8 Smoke tests after promotion | FR-DEL-11 |  |
| 9 CI/CD, environments, versions | FR-DEL-4, FR-DEL-5, FR-DEL-6, FR-DEL-7, FR-DEL-8, FR-DEL-12, FR-DEL-13, FR-DEL-14, FR-DEL-15, FR-DEL-22, FR-DEL-23 |  |
| 10 Repository as code and policy as code | FR-DEL-2, FR-DEL-8, FR-DEL-23, FR-POL-1, FR-POL-2, FR-POL-3, FR-POL-4, FR-POL-5, FR-POL-9 |  |
| 12 Cost and FinOps (controls) | NFR-COST-1, NFR-COST-2, NFR-COST-3, FR-COST-1, FR-COST-2, FR-COST-3, FR-COST-5, FR-COST-6 |  |
| 14 Zero manual actions, break-glass | FR-SEC-7, FR-DEL-24, FR-DEL-25 |  |
| 15 Monitoring as code | FR-DEL-21, FR-OBS-2, FR-OBS-5, FR-OBS-6, FR-OBS-13, FR-OBS-14 |  |
| 16 Admin interfaces and access | FR-SEC-27, FR-SEC-28 |  |
| 17 Helm charts and migration Jobs | FR-INF-25, FR-INF-26, FR-INF-27, FR-INF-28, FR-DAT-23 |  |
| 18 Infrastructure autotests | FR-DEL-20, FR-DEL-21, FR-OBS-25 |  |
| 19 Backups and restore as code | FR-DAT-11, FR-DAT-13, FR-DAT-16, FR-DAT-19, FR-POL-6, FR-POL-7, FR-POL-14 |  |
| 20.1 Database access as code | FR-SEC-10 |  |
| 20.2 Kafka as code | FR-DAT-4, FR-POL-15 |  |
| 20.3 Vault as code and rotation | FR-SEC-25 |  |
| 20.4 Compliance as code (PCI DSS) | FR-SEC-22, FR-SEC-23, FR-POL-12 |  |
| 20.5 Supply chain | FR-SEC-12, FR-SEC-15, FR-SEC-16, FR-DEL-5, FR-POL-4 |  |
| 20.6 On-call and incidents as code | FR-OBS-15, FR-OBS-16 |  |
| 20.7 Feature flags as code | - | No requirement in this baseline |
| 20.8 DNS and certificates | FR-INF-30, FR-INF-31 |  |
| 20.9 Cost as code | NFR-COST-1 |  |
| 20.10 Developer environment | FR-POL-17 |  |
| 20.11 Architecture diagrams as code | - | No requirement in this baseline |
| 20.12 Threat model as code | - | No requirement in this baseline |
| 21.1 Hot merchant split (ADR-016) | FR-INF-9, FR-INF-10 |  |
| 21.2 Semi-automatic DR failover (ADR-015) | FR-OBS-11 | one-confirmation switch superseded by ADR-0017 |
| 21.3 ClickHouse self-managed and exit plan | NFR-REC-7 |  |
| 21.5 Alignment of sections | FR-DAT-11 |  |
| 22.1 Tag schema | FR-POL-18 |  |
| 22.2 How tags reach resources | FR-POL-18 |  |
| 22.3 Checks and protection | FR-POL-19, FR-POL-20 |  |
| 22.4 Resource grouping | FR-POL-21 |  |
| 22.5 Cost and observation by tags | FR-COST-1 |  |
| 22.6 Tests | FR-POL-19 |  |
| 23 Zero trust (intro) | FR-SEC-7 |  |
| 23.1 Principles | FR-SEC-5, FR-SEC-6, FR-SEC-18 |  |
| 23.2 IAM least privilege | FR-INF-23, FR-SEC-6, FR-SEC-9 |  |
| 23.3 Automation roles | FR-SEC-11, FR-SEC-12, FR-SEC-13, FR-DEL-22 |  |
| 23.4 Kubernetes and Argo CD RBAC | FR-SEC-14, FR-SEC-17 |  |
| 23.5 Claude Code agents and MCP | FR-SEC-29, FR-COST-6, FR-OBS-17 |  |
| 23.6 Secrets and long-lived credentials | FR-SEC-24 |  |
| 23.7 Device posture (Verified Access) | - | No requirement in this baseline |
| 23.8 External dependencies | FR-INF-4 |  |
| 23.9 Automatic checks | FR-SEC-8 |  |
| 24.1 Base formula | FR-DAT-7 |  |
| 24.2 Policy per dependency | FR-DAT-6, FR-DAT-7 |  |
| 24.3 Golden rules | FR-DAT-6 |  |
| 24.4 Istio and Helm | FR-DAT-9 |  |
| 24.5 Metrics and alerts | FR-DAT-8 |  |
| 24.6 Checks | FR-POL-16 |  |
| 25.1 Failure-mode catalog | FR-OBS-9 |  |
| 25.2 Layers and minimums | NFR-COV-1 |  |
| 25.3 Coverage calculation | NFR-COV-3, FR-OBS-7, FR-OBS-9, FR-OBS-16 |  |
| 25.4 An alert that never fires does not count | NFR-COV-2, NFR-COV-3, FR-OBS-12 |  |
| 25.5 Alert quality | FR-OBS-8 |  |
| 26.1 EC2NodeClass | FR-INF-21, FR-SEC-26 |  |
| 26.2 NodePool and CDE isolation | FR-INF-22 |  |
| 26.3 Node role and pod permissions | FR-INF-23 |  |
| 26.4 Node image and patches | FR-INF-21 |  |
| 26.5 Automatic checks | FR-SEC-26 |  |
| 26.6 Alerts (compute layer) | FR-INF-21 |  |
| 27.5 Branching strategy | FR-DEL-1, FR-DEL-14, FR-DEL-16 |  |
| 27.6 Branches and tags drive CI/CD | FR-DEL-3, FR-DEL-6 |  |

## Owner decisions and ADRs

| Decision | Requirement IDs | Note |
|---|---|---|
| D1 | FR-DEL-17, FR-DEL-18, FR-DEL-19 | |
| D2 | NFR-REC-11, NFR-REC-13, FR-DAT-11, FR-DAT-12, FR-DAT-20, FR-POL-5, FR-POL-6, FR-POL-7, FR-OBS-10 | |
| D3 | NFR-REC-7, NFR-REC-9, NFR-REC-14, FR-DAT-11, FR-DAT-17, FR-DAT-22, FR-POL-8 | |
| D4 | NFR-REC-12, FR-INF-3, FR-DAT-15, FR-DAT-19, FR-DAT-20, FR-DAT-21, FR-OBS-10 | |
| D5 | NFR-REC-15, FR-DAT-14, FR-POL-13, FR-COST-5 | |
| D6 | FR-INF-11, FR-INF-12, FR-INF-14, FR-DAT-10, FR-DAT-26 | |
| D7 | NFR-REC-2, NFR-REC-3, NFR-REC-4, NFR-REC-5, NFR-REC-6, NFR-REC-8, NFR-REC-10, NFR-REC-17, NFR-REC-18, NFR-REC-21, FR-INF-14, FR-INF-16, FR-INF-17, FR-INF-19, FR-DAT-5, FR-DAT-14, FR-DAT-17, FR-DAT-18, FR-DAT-21, FR-DAT-25, FR-DAT-27, FR-POL-10, FR-POL-11, FR-OBS-10, FR-OBS-11, FR-OBS-24 | |
| D8 | NFR-REC-16, FR-DAT-24, FR-OBS-10 | |
| ADR-001 CDE in separate accounts | FR-INF-1 |  |
| ADR-002 MemoryDB for KV and streams | FR-DAT-1, FR-DAT-2 |  |
| ADR-003 Aurora PostgreSQL | FR-DAT-3 |  |
| ADR-004 Warm standby between regions | NFR-REC-19, NFR-REC-20, FR-INF-6, FR-INF-12, FR-INF-13, FR-INF-14, FR-INF-15, FR-DAT-26, FR-COST-4, FR-OBS-11 | superseded by ADR-0017 |
| ADR-005 Istio sidecar | FR-SEC-3 |  |
| ADR-006 Shield Advanced | FR-SEC-30 |  |
| ADR-007 Global Accelerator and NLB | FR-INF-18 |  |
| ADR-008 EKS | FR-INF-20 |  |
| ADR-009 Terraform and Terragrunt | FR-INF-16 |  |
| ADR-010 Argo CD | FR-DEL-9 |  |
| ADR-011 ClickHouse self-managed | FR-INF-24 |  |
| ADR-012 Network Firewall for PSP egress | FR-INF-4 |  |
| ADR-013 Cells | FR-INF-8 |  |
| ADR-013a Shared locker | NFR-SLO-6, FR-INF-8 |  |
| ADR-013b Locker survives KMS, writer and bad version | FR-SEC-2, FR-DEL-10 |  |
| ADR-015 Semi-automatic DR failover (section 21.2) | NFR-REC-19, NFR-REC-20, FR-INF-6, FR-INF-12, FR-INF-13, FR-INF-14, FR-INF-15, FR-DAT-26, FR-COST-4, FR-OBS-11 | confirmation step superseded by ADR-0017; detection kept (FR-OBS-11) |
| ADR-016 Hot merchant split (section 21.1) | FR-INF-10 |  |
| ADR-0017 Region model (docs/adr/0017-recovery-region-data-replication.md) | NFR-REC-19, NFR-REC-20, FR-INF-6, FR-INF-12, FR-INF-13, FR-INF-14, FR-INF-15, FR-DAT-26, FR-COST-4, FR-OBS-11 |  |

## Out of scope

| Source part | Reason |
|---|---|
| 11 Claude Code commands, skills, MCP, subagents, orchestration | repository process, governed by `CLAUDE.md` |
| 14 Repository tree, directory naming, glossary extract | repository process; terms in `docs/glossary.md` |
| 18 Repository tree, agent models, code comments, refactoring | repository process, governed by `CLAUDE.md` and `AGENTS.md` |
| 21.4 Comment linter | repository process |
| 21.5 Claude Code bullet | repository process |
| 27.1 to 27.4 Authorship, commit split, commit messages, PR description | repository process, governed by `CLAUDE.md` |
| 27.7 AI review | repository process |
| 27.8 Issues, milestones, projects | repository process |
| 2 and 6 business behavior (PSP routing, merchant API authentication, webhook signing, routing between cells by hash, tokenization logic) | business behavior of the payment services |
| Withdrawn passages of `srs.md` section 6 | withdrawn by D6 and D7 |

## Requirement to artefact

The verifying artefact is the first artefact named in the Implementation column of the requirement.

| File | Requirement | Verification | Verifying artefact | Source |
|---|---|---|---|---|
| nfr.md | NFR-CAP-1 | test | `tests/load/scenarios/average.js` | Section 1 |
| nfr.md | NFR-CAP-2 | test | `tests/load/scenarios/daily-peak.js` | Section 1 |
| nfr.md | NFR-CAP-3 | test | `tests/load/scenarios/sale-peak.js` | Section 1, section 8 |
| nfr.md | NFR-CAP-4 | test | `tests/load/scenarios/stress.js` | Section 1, section 8 |
| nfr.md | NFR-CAP-5 | analysis | `CALLS_PER_PAYMENT = 7` | Section 1 |
| nfr.md | NFR-CAP-6 | test | `tests/load/scenarios/soak.js` | Section 8 |
| nfr.md | NFR-SLO-1 | metric | `observability/slo/authorization-availability.yaml` | Section 1 |
| nfr.md | NFR-SLO-2 | metric | `observability/slo/platform-overhead-latency.yaml` | Section 1 |
| nfr.md | NFR-SLO-3 | metric | `observability/slo/payment-status-read.yaml` | Section 1 |
| nfr.md | NFR-SLO-4 | metric | `observability/slo/merchant-webhook-delivery.yaml` | Section 1 |
| nfr.md | NFR-SLO-5 | metric | `DrainLagHigh` | Section 2, section 13 |
| nfr.md | NFR-SLO-6 | metric | `LockerErrorRateHigh` | Section 13 (ADR-013a) |
| nfr.md | NFR-REC-1 | test | `tests/chaos/fis/az-loss.json` | Section 1 |
| nfr.md | NFR-REC-2 | metric | `AuroraGlobalLagHigh` | D7 |
| nfr.md | NFR-REC-3 | test | `tests/chaos/region-switch/scenario.json` | D7 |
| nfr.md | NFR-REC-4 | test | `infra/live/<env>/<region>/locker/aurora` | D7 |
| nfr.md | NFR-REC-5 | metric | `DynamoDbGlobalTableLagHigh` | D7 |
| nfr.md | NFR-REC-6 | metric | `infra/modules/s3-backup` | D7 |
| nfr.md | NFR-REC-7 | test | `infra/modules/clickhouse` | Section 1, D3, section 21.3 |
| nfr.md | NFR-REC-8 | metric | `infra/modules/backup` | D7 |
| nfr.md | NFR-REC-9 | inspection | `deploy/` | Section 1, D3 |
| nfr.md | NFR-REC-10 | test | `RECONCILE_WINDOW_MINUTES = 5` | D7 |
| nfr.md | NFR-REC-11 | metric | `aurora-global` | D2 |
| nfr.md | NFR-REC-12 | metric | `RestoreTargetSeconds` | D4 |
| nfr.md | NFR-REC-13 | metric | `gold` | D2 |
| nfr.md | NFR-REC-14 | test | `gold` | D3 |
| nfr.md | NFR-REC-15 | test | `infra/modules/s3-backup` | D5 |
| nfr.md | NFR-REC-16 | test | `warmup.minRatio: 0.75` | D8 |
| nfr.md | NFR-REC-17 | test | `infra/modules/aurora-global` | D7 |
| nfr.md | NFR-REC-18 | test | `wait-capacity-us-east-1` | D7 |
| nfr.md | NFR-REC-21 | test | `budget_min` | D7 |
| nfr.md | NFR-REC-19 | test | `alarm_evaluation_periods = 5` | ADR-0017 |
| nfr.md | NFR-REC-20 | test | `MAX_FAILBACK_LAG_MS = 1000` | ADR-0017 |
| nfr.md | NFR-COST-1 | inspection | `infra/live/**` | Section 12, section 20.9 |
| nfr.md | NFR-COST-2 | test | `aws_budgets_budget` | Section 12 |
| nfr.md | NFR-COST-3 | analysis | `observability/dashboards/finops/cost.json` | Section 12 |
| nfr.md | NFR-COV-1 | test | `observability/coverage/targets.yaml` | Section 25.2 |
| nfr.md | NFR-COV-2 | metric | `detect_within` | Section 25.4 |
| nfr.md | NFR-COV-3 | test | `promtool test rules` | Section 25.3, section 25.4 |
| infrastructure.md | FR-INF-1 | test | `infra/aft-account-requests/accounts/{infrastructure,workloads-cde,sandbox}.yaml` | Section 3 (Landing Zone), ADR-001 |
| infrastructure.md | FR-INF-2 | test | `infra/modules/vpc` | Section 3 (network) |
| infrastructure.md | FR-INF-3 | test | `infra/modules/vpc` | Section 3 (network), D4 |
| infrastructure.md | FR-INF-4 | test | `infra/modules/network-firewall` | Section 3 (network), section 23.8, ADR-012 |
| infrastructure.md | FR-INF-5 | test | `infra/modules/transit-gateway` | Section 3 (network) |
| infrastructure.md | FR-INF-6 | inspection | `infra/live/<env>/{eu-central-1,us-east-1}/{egress-vpc,firewall,tgw}` | ADR-0017 |
| infrastructure.md | FR-INF-7 | test | `flow_logs_bucket_arn` | Section 3 (network), section 6 |
| infrastructure.md | FR-INF-8 | inspection | `infra/live/<env>/eu-central-1/{cell-0..cell-3,spare}/{eks,karpenter,memorydb,aurora,data-access,iam-workloads}` | Section 2 (cells), ADR-013, ADR-013a, section 1 |
| infrastructure.md | FR-INF-9 | test | `infra/modules/dynamodb-global` | Section 2 (cells), section 21.1 |
| infrastructure.md | FR-INF-10 | test | `scripts/cells/migrate-merchant.py` | Section 21.1 (ADR-016) |
| infrastructure.md | FR-INF-11 | test | `writer_az` | D6, section 4 |
| infrastructure.md | FR-INF-12 | test | `region_role = working` | D6, ADR-0017 |
| infrastructure.md | FR-INF-13 | inspection | `infra/live/<env>/us-east-1/{cell-0..cell-3,spare,locker}` | ADR-0017 |
| infrastructure.md | FR-INF-14 | inspection | `infra/live/<env>/us-east-2/{vpc,kms,ecr,restore-test}` | D6, D7, ADR-0017 |
| infrastructure.md | FR-INF-15 | test | `infra/modules/dns-routing` | ADR-0017 |
| infrastructure.md | FR-INF-16 | test | `_envcommon/compute/{eks,karpenter}.hcl` | D7, ADR-009 |
| infrastructure.md | FR-INF-17 | test | `infra/modules/dr-failover` | D7 |
| infrastructure.md | FR-INF-18 | test | `infra/modules/global-accelerator` | Section 3, ADR-007 |
| infrastructure.md | FR-INF-19 | test | `infra/modules/{kms,secrets-replica,ecr,network-firewall}` | D7 |
| infrastructure.md | FR-INF-20 | test | `infra/modules/eks` | Section 4 (clusters), ADR-008 |
| infrastructure.md | FR-INF-21 | test | `manifests` | Section 26.1, section 26.4, section 26.6 |
| infrastructure.md | FR-INF-22 | test | `cde` | Section 26.2 |
| infrastructure.md | FR-INF-23 | test | `infra/modules/iam-workloads` | Section 26.3, section 23.2 |
| infrastructure.md | FR-INF-24 | inspection | `infra/live/<env>/eu-central-1/analytics/{eks,karpenter,msk,opensearch,clickhouse}` | Section 2, ADR-011 |
| infrastructure.md | FR-INF-25 | test | `tools/lint/structure` | Section 17 |
| infrastructure.md | FR-INF-26 | test | `deploy/charts/<chart>/` | Section 17 |
| infrastructure.md | FR-INF-27 | inspection | `deploy/envs/{dev,stage,prod}/<region>/<cell>/values.yaml` | Section 17 |
| infrastructure.md | FR-INF-28 | test | `deploy/charts/{payments-cell,payments-locker,payments-edge}/Chart.yaml` | Section 17 |
| infrastructure.md | FR-INF-29 | test | `deploy/platform/gateway-api-crds` | Section 4, owner decision |
| infrastructure.md | FR-INF-30 | test | `infra/modules/dns-certs` | Section 20.8 |
| infrastructure.md | FR-INF-31 | test | `CertificateExpiryCritical` | Section 20.8 |
| data-and-recovery.md | FR-DAT-1 | metric | `DrainLagHigh` | Section 2 (write path), ADR-002 |
| data-and-recovery.md | FR-DAT-2 | test | `infra/modules/memorydb` | Section 5, ADR-002 |
| data-and-recovery.md | FR-DAT-3 | test | `infra/modules/aurora-global` | Section 5 (PostgreSQL), ADR-003 |
| data-and-recovery.md | FR-DAT-4 | test | `infra/modules/msk` | Section 5, section 20.2 |
| data-and-recovery.md | FR-DAT-5 | inspection | `sink_role_arn` | D7 |
| data-and-recovery.md | FR-DAT-6 | test | `psp-authorize` | Section 2 (PSP), section 24.2, section 24.3 |
| data-and-recovery.md | FR-DAT-7 | test | `defaults` | Section 24.1, section 24.2 |
| data-and-recovery.md | FR-DAT-8 | test | `RetryStorm` | Section 24.5 |
| data-and-recovery.md | FR-DAT-9 | test | `retry_policy` | Section 24.4 |
| data-and-recovery.md | FR-DAT-10 | analysis | `failover-global-cluster` | Section 2 (CAP and PACELC), D6 |
| data-and-recovery.md | FR-DAT-11 | test | `infra/modules/backup` | D2, D3, section 19, section 21.5 |
| data-and-recovery.md | FR-DAT-12 | test | `backup_retention_days = 35` | D2 |
| data-and-recovery.md | FR-DAT-13 | test | `infra/modules/backup` | Section 19, section 6 |
| data-and-recovery.md | FR-DAT-14 | test | `infra/modules/s3-backup` | D5, D7 |
| data-and-recovery.md | FR-DAT-15 | test | `clickhouse-backup` | D4 |
| data-and-recovery.md | FR-DAT-16 | test | `BackupJobFailed` | Section 19 (monitoring) |
| data-and-recovery.md | FR-DAT-17 | test | `infra/modules/memorydb` | D3, D7 |
| data-and-recovery.md | FR-DAT-18 | test | `recovery_regions` | D7 |
| data-and-recovery.md | FR-DAT-19 | test | `infra/modules/restore-automation` | D4, section 19 |
| data-and-recovery.md | FR-DAT-20 | metric | `RestoreDurationSeconds` | D2, D4 |
| data-and-recovery.md | FR-DAT-21 | inspection | `infra/live/prod/us-east-2/restore-test` | D4, D7 |
| data-and-recovery.md | FR-DAT-22 | test | `scripts/schema/pre-migration-snapshot.sh` | D3 |
| data-and-recovery.md | FR-DAT-23 | test | `tools/ci/migrations/migration_check.py` | Section 5 (migrations), section 17 |
| data-and-recovery.md | FR-DAT-24 | test | `warmup` | D8 |
| data-and-recovery.md | FR-DAT-25 | test | `deny_recovery_writes` | D7 |
| data-and-recovery.md | FR-DAT-26 | test | `FENCE_RULE` | D6, ADR-0017 |
| data-and-recovery.md | FR-DAT-27 | metric | `OrphanPaymentWebhooks` | D7 |
| security-and-access.md | FR-SEC-1 | test | `policy/semgrep/no-pan-logging.yaml` | Section 6 (card data) |
| security-and-access.md | FR-SEC-2 | test | `policy/opa/terraform/kms-cmk-required` | Section 6, section 13 (ADR-013b) |
| security-and-access.md | FR-SEC-3 | test | `tls` | Section 6 (encryption in transit), ADR-005 |
| security-and-access.md | FR-SEC-4 | test | `policy/opa/terraform/cde-no-public` | Section 6, section 3 |
| security-and-access.md | FR-SEC-5 | test | `infra/modules/identity-center` | Section 6 (identity), section 23.1 |
| security-and-access.md | FR-SEC-6 | test | `cde_jit_grants` | Section 23.1, section 23.2 |
| security-and-access.md | FR-SEC-7 | test | `BreakGlassRoleUsed` | Section 14 (zero manual actions), section 23 |
| security-and-access.md | FR-SEC-8 | test | `IamChangeOutsideTerraform` | Section 23.9 |
| security-and-access.md | FR-SEC-9 | test | `policy/opa/terraform/iam-no-wildcard` | Section 23.2 |
| security-and-access.md | FR-SEC-10 | test | `infra/modules/data-access` | Section 20.1 |
| security-and-access.md | FR-SEC-11 | test | `infra/modules/ci-oidc-roles` | Section 23.3 |
| security-and-access.md | FR-SEC-12 | test | `policy/opa/github/permissions-at-job-level` | Section 23.3, section 20.5 |
| security-and-access.md | FR-SEC-13 | test | `infra/modules/ci-runners` | Section 23.3 |
| security-and-access.md | FR-SEC-14 | test | `access_entries` | Section 23.4 |
| security-and-access.md | FR-SEC-15 | test | `require-image-digest` | Section 20.5 |
| security-and-access.md | FR-SEC-16 | test | `policy/opa/docker/distroless` | Section 20.5 |
| security-and-access.md | FR-SEC-17 | test | `policy/kyverno/cde-no-exec` | Section 6, section 23.4 |
| security-and-access.md | FR-SEC-18 | test | `platform-common` | Section 6 (perimeter), section 23.1 |
| security-and-access.md | FR-SEC-19 | test | `secrets` | Section 6 (DevSecOps) |
| security-and-access.md | FR-SEC-20 | test | `.github/workflows/codeql.yml` | Section 6 (DevSecOps) |
| security-and-access.md | FR-SEC-21 | test | `infra/modules/org-security-services` | Section 6 (perimeter and detection) |
| security-and-access.md | FR-SEC-22 | test | `policy/scp/security-baseline.json` | Section 20.4 |
| security-and-access.md | FR-SEC-23 | test | `infra/modules/log-archive` | Section 6, section 20.4 |
| security-and-access.md | FR-SEC-24 | test | `infra/modules/secrets-replica` | Section 6 (secrets), section 23.6 |
| security-and-access.md | FR-SEC-25 | test | `deploy/platform/vault` | Section 20.3 |
| security-and-access.md | FR-SEC-26 | test | `infra/modules/karpenter` | Section 26.1, section 26.5 |
| security-and-access.md | FR-SEC-27 | test | `infra/modules/admin-edge` | Section 16 |
| security-and-access.md | FR-SEC-28 | test | `groups` | Section 16 |
| security-and-access.md | FR-SEC-29 | test | `config/admin-agent.yaml` | Section 23.5 |
| security-and-access.md | FR-SEC-30 | test | `aws_shield_subscription` | Section 6 (perimeter), ADR-006 |
| delivery.md | FR-DEL-1 | test | `infra/github/modules/rulesets` | Section 27.5 |
| delivery.md | FR-DEL-2 | test | `required_approving_review_count = var.main_approvals` | Section 10 |
| delivery.md | FR-DEL-3 | test | `commitlint` | Section 27.6 |
| delivery.md | FR-DEL-4 | test | `changes` | Section 9 (pipeline) |
| delivery.md | FR-DEL-5 | test | `.github/workflows/images.yml` | Section 9 (images), section 20.5 |
| delivery.md | FR-DEL-6 | test | `.github/workflows/promote.yml` | Section 9 (environments), section 27.6 |
| delivery.md | FR-DEL-7 | test | `promotion` | Section 9 |
| delivery.md | FR-DEL-8 | test | `infra/github/modules/rulesets` | Section 9, section 10 |
| delivery.md | FR-DEL-9 | test | `deploy/argocd/templates/applicationset-gated.yaml` | Section 4 (GitOps), ADR-010 |
| delivery.md | FR-DEL-10 | test | `rollout` | Section 4 (deployment strategies), ADR-013b |
| delivery.md | FR-DEL-11 | test | `deploy/platform/smoke/job` | Section 8 (smoke tests) |
| delivery.md | FR-DEL-12 | inspection | `concurrency` | Section 9 |
| delivery.md | FR-DEL-13 | test | `.github/workflows/tag-deployed.yml` | Section 9 (version lifecycle) |
| delivery.md | FR-DEL-14 | test | `.github/workflows/hotfix.yml` | Section 9, section 27.5 |
| delivery.md | FR-DEL-15 | test | `hotfix-guard` | Section 9 |
| delivery.md | FR-DEL-16 | test | `backport` | Section 27.5 |
| delivery.md | FR-DEL-17 | test | `.github/workflows/tag.yml` | D1 |
| delivery.md | FR-DEL-18 | test | `refs/tags/v*` | D1 |
| delivery.md | FR-DEL-19 | test | `evidence` | D1 |
| delivery.md | FR-DEL-20 | test | `make lint-terraform test-terraform` | Section 18 (infrastructure autotests) |
| delivery.md | FR-DEL-21 | test | `make lint-helm test-helm test-policy` | Section 18, section 15 |
| delivery.md | FR-DEL-22 | test | `pay-<env>-glob-tf-plan` | Section 9 (IaC), section 23.3 |
| delivery.md | FR-DEL-23 | test | `drift` | Section 9, section 10 |
| delivery.md | FR-DEL-24 | inspection | `promote.yml` | Section 14 (zero manual actions) |
| delivery.md | FR-DEL-25 | test | `tools/ci/placeholder_report.py` | Section 14 |
| policy-and-cost.md | FR-POL-1 | test | `infra/github/` | Section 10 (repository as code) |
| policy-and-cost.md | FR-POL-2 | test | `infra/github/modules/repository` | Section 10 |
| policy-and-cost.md | FR-POL-3 | test | `infra/github/config/owners.yaml` | Section 10 |
| policy-and-cost.md | FR-POL-4 | inspection | `renovate.json5` | Section 10, section 20.5 |
| policy-and-cost.md | FR-POL-5 | test | `policy/opa/terraform/no-stateful-without-backup` | D2, section 10 |
| policy-and-cost.md | FR-POL-6 | test | `policy/opa/terraform/backup-tier-required` | D2, section 19 |
| policy-and-cost.md | FR-POL-7 | test | `policy/opa/lib/exceptions` | D2, section 19 |
| policy-and-cost.md | FR-POL-8 | test | `policy/kyverno/require-migration-snapshot` | D3 |
| policy-and-cost.md | FR-POL-9 | test | `policy/kyverno/require-probes` | Section 10, section 4 |
| policy-and-cost.md | FR-POL-10 | test | `policy/scp/region-allow-list.json` | D7, section 3 |
| policy-and-cost.md | FR-POL-11 | test | `policy/scp/deny-dynamodb-writes-recovery-regions.json` | D7 |
| policy-and-cost.md | FR-POL-12 | test | `policy/config/pci-dss-pack/pci-dss-v4.yaml` | Section 20.4 |
| policy-and-cost.md | FR-POL-13 | test | `policy/opa/terraform/s3-object-lock-required` | D5, section 6 |
| policy-and-cost.md | FR-POL-14 | test | `policy/scp/backup-policies/backup-tiers.json` | Section 19 |
| policy-and-cost.md | FR-POL-15 | test | `infra/modules/msk` | Section 20.2 |
| policy-and-cost.md | FR-POL-16 | test | `policy/resilience/policy.yaml` | Section 24.6 |
| policy-and-cost.md | FR-POL-17 | inspection | `mise.toml` | Section 20.10 |
| policy-and-cost.md | FR-POL-18 | test | `policy/tagging/schema.yaml` | Section 22.1, section 22.2 |
| policy-and-cost.md | FR-POL-19 | test | `policy/scp/tag-policies/required-tags.json` | Section 22.3, section 22.6 |
| policy-and-cost.md | FR-POL-20 | test | `policy/scp/deny-tag-edit.json` | Section 22.3 |
| policy-and-cost.md | FR-POL-21 | test | `policy/tagging/tests/org-trees-values-test.rego` | Section 22.4 |
| policy-and-cost.md | FR-COST-1 | inspection | `observability/dashboards/finops/cost.json` | Section 12 (visibility), section 22.5 |
| policy-and-cost.md | FR-COST-2 | test | `spot_pools` | Section 12 (price type) |
| policy-and-cost.md | FR-COST-3 | test | `infra/modules/ci-runners` | Section 12 (schedules) |
| policy-and-cost.md | FR-COST-4 | inspection | `standby.node_pool_cpu_limits` | ADR-0017 |
| policy-and-cost.md | FR-COST-5 | test | `infra/modules/s3-backup` | D5, section 12 |
| policy-and-cost.md | FR-COST-6 | test | `aws_budgets_budget.bedrock` | Section 12, section 23.5 |
| observability-and-testing.md | FR-OBS-1 | test | `observability/otel/collector.yaml` | Section 7 |
| observability-and-testing.md | FR-OBS-2 | test | `observability/standards/labels.yaml` | Section 7, section 15 |
| observability-and-testing.md | FR-OBS-3 | test | `tests/contracts/test_platform_ha.py` | Section 7 |
| observability-and-testing.md | FR-OBS-4 | test | `AuthorizationRateDrop` | Section 7 (business metrics) |
| observability-and-testing.md | FR-OBS-5 | test | `observability/exporters/*.yaml` | Section 15 (exporters) |
| observability-and-testing.md | FR-OBS-6 | test | `observability/slo/generate.py` | Section 15 (alerts and SLO as code) |
| observability-and-testing.md | FR-OBS-7 | test | `observability/tests/test_contract.py` | Section 25.3 |
| observability-and-testing.md | FR-OBS-8 | test | `observability/tests/test_alert_timers.py` | Section 25.5 |
| observability-and-testing.md | FR-OBS-9 | test | `observability/coverage/alert_coverage.py` | Section 25.3, section 25.1 |
| observability-and-testing.md | FR-OBS-10 | test | `observability/alerts/backup-dr/{replication,restore}.yaml` | D2, D4, D7, D8 |
| observability-and-testing.md | FR-OBS-11 | test | `RegionDown` | D7, section 21.2, ADR-0017 |
| observability-and-testing.md | FR-OBS-12 | test | `Watchdog` | Section 25.4 |
| observability-and-testing.md | FR-OBS-13 | test | `observability/lib/build.py` | Section 15 (dashboards) |
| observability-and-testing.md | FR-OBS-14 | inspection | `observability/dashboards/l1-services/slow-requests.json` | Section 15 |
| observability-and-testing.md | FR-OBS-15 | test | `observability/alertmanager/alertmanager.yaml` | Section 20.6 |
| observability-and-testing.md | FR-OBS-16 | test | `docs/runbooks/<layer>/<alert>.md` | Section 20.6, section 25.3 |
| observability-and-testing.md | FR-OBS-17 | test | `tools/ai/admin_agent` | Section 7 (AIOps), section 23.5 |
| observability-and-testing.md | FR-OBS-18 | test | `autoscaling` | Section 8 (replicas and autoscaling) |
| observability-and-testing.md | FR-OBS-19 | test | `cpu_limits` | Section 8 |
| observability-and-testing.md | FR-OBS-20 | test | `docs/capacity/capacity.py` | Section 8 |
| observability-and-testing.md | FR-OBS-21 | test | `tests/load/` | Section 8 (load tests) |
| observability-and-testing.md | FR-OBS-22 | test | `tests/chaos/fis/*.json` | Section 8 (chaos engineering) |
| observability-and-testing.md | FR-OBS-23 | test | `tests/chaos/fis/{az-loss,node-loss,workers-spot-interruption,aurora-writer-failover,memorydb-failover,msk-broker-loss}.json` | Section 8 |
| observability-and-testing.md | FR-OBS-24 | test | `tests/chaos/region-switch/{scenario,plan-b}.json` | D7 |
| observability-and-testing.md | FR-OBS-25 | test | `tests/contracts/test_{alert_contracts,telemetry_path,values_schema,platform_ha}.py` | Section 18 |
