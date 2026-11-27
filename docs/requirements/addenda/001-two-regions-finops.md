---
id: 001-two-regions-finops
status: draft
spec: specs/001-devops-platform
---

# Addendum 001-two-regions-finops: two regions with a hot standby in us-east-1, and the FinOps sizes

These changes follow two decisions.

- **Region model ([ADR-0019](../../adr/0019-hot-standby-recovery-region.md)).** The platform has two regions. eu-central-1 writes. us-east-1 is a hot standby for prod only, running at the working size. The second recovery region is removed. Stage and dev run in eu-central-1 alone.
- **FinOps sizes.** These are the adopted findings of `docs/architecture/cost/audit.md`. The audit's pilot-light finding was rejected by the owner.

The baseline narrative in `srs.md` reads with the rows below:

- the scope line on the recovery region;
- the ADR-0017 notes under D6 and D7;
- the `recovery region` term;
- the audit-copy line;
- the section 12 cost row.

Wherever that narrative names a second recovery region, a plan B, a warm standby or a data-only region, it is replaced by the us-east-1 hot standby of prod. The recovery VPC CIDRs of D7 (10.102.0.0/16, 10.103.0.0/16) are replaced by the per-environment ranges in `config/platform.yaml` (`network`). Only the us-east-1 range of prod is in use.

## Changed

| ID | Requirement | Verification | Implementation | Source |
|---|---|---|---|---|
| FR-INF-8 | The working region shall run four working cells and one spare cell in stage and prod, and cell-0 and the spare in dev, each with its own EKS cluster, MemoryDB and Aurora, and one locker Aurora shared by all cells. | inspection | `cells` in `infra/live/<env>/env.hcl`; `infra/live/<env>/eu-central-1/{cell-*,spare,locker}`. | FinOps audit finding 7 (dev), ADR-013, ADR-013a |
| FR-INF-13 | In prod, us-east-1 shall run a hot standby at the working size: per cell and for the spare an EKS cluster with the working-region node pools and workload floors and MemoryDB with the working shard count, and one Aurora instance per global secondary with the writer class of its working cluster, serving no requests while Frankfurt is healthy. | inspection | `standby.compute_enabled: true` in `config/environments/prod.yaml`; `infra/live/prod/us-east-1/{cell-*,spare,locker}`; `deploy/envs/prod/us-east-1/`. | ADR-0019 |
| FR-INF-15 | The public API name shall resolve to Frankfurt while its HTTPS health check passes, and to us-east-1 only when the Frankfurt check fails and the us-east-1 ingress passes its own check. | test | Route 53 failover records of `infra/modules/dns-routing` (`/health/deep` checks), stack `edge-dns-routing`; `infra/modules/dns-routing/tests/dns-routing.tftest.hcl`. | ADR-0019 |
| FR-INF-16 | Node pools in both regions shall allow several instance families and both CPU architectures, and a region switch shall need no new capacity because the standby runs at the working size. | test | `instance_families` of `infra/modules/karpenter` (m7g, m6g, m7i, m6i; r7g, r6g, r7i, r6i; arm64 and amd64) and its `tests/`; FR-INF-13. | D7, ADR-0019 |
| FR-COST-4 | Only prod shall have a standby region; stage and dev shall have no recovery-region stacks except `panel-edge`, `waf-edge` and `kms` in us-east-1. | inspection | `infra/live/{stage,dev}/us-east-1/{panel-edge,waf-edge,kms}` only; `standby.enabled: false` in `config/environments/dev.yaml`. | ADR-0019, FinOps audit finding 7 |
| FR-DAT-2 | MemoryDB of each working cell shall run 2 shards of 1 primary and 2 replicas over three AZs, and the spare 1 shard until it takes a merchant, with TLS, ACL users and `maxmemory-policy noeviction`. | test | `infra/modules/memorydb` and its `tests/`; `num_shards = 1` in `infra/live/prod/eu-central-1/spare/memorydb`; alerts `MemoryDbMemoryCritical` and `MemoryDbEvictions`. | Section 5, ADR-002, FinOps audit finding 3 |
| FR-DAT-3 | Aurora PostgreSQL 16 of every cell and of the locker shall use readers, RDS Proxy, forced TLS 1.3, `pg_stat_statements` and pgaudit; the working cells use I/O-Optimized storage, and the spare and the locker use Standard storage. | test | `storage_type` of `infra/modules/aurora-global` (`aurora` for spare and locker); its parameter groups and proxy; `tests/aurora-global.tftest.hcl`. | Section 5, ADR-003, FinOps audit finding 9 |
| FR-DAT-4 | MSK in prod shall run 3 brokers over three AZs with replication factor 3, `min.insync.replicas=2`, IAM authentication only, TLS and topic auto-creation off. | test | `analytics.msk` in `infra/live/prod/env.hcl` (3 x `kafka.m7g.large`, 1,000 GB); `infra/modules/msk` and its `tests/`; alerts `KafkaUnderReplicatedPartitions`, `KafkaConsumerLagHigh`, `KafkaBrokerDiskHigh`. | Section 5, section 20.2, FinOps audit finding 5 |
| FR-DAT-11 | Every stateful resource shall join an AWS Backup plan by its `backup-tier` tag: gold hourly 35 days with copies to us-east-1 in prod, continuous 35 days and monthly 7 years; silver hourly 35 days with that copy; bronze daily 7 days. Stage and dev keep their backups in eu-central-1 only. | test | `infra/modules/backup` and its `tests/`; `recovery_regions` absent in `infra/live/{stage,dev}/eu-central-1/backup`; OPA `policy/opa/terraform/backup-tier-required`. | D2, D3, section 19, section 21.5, ADR-0019 |
| FR-DAT-14 | Object backups, audit logs, the event archive and Terraform state shall be kept in versioned KMS-encrypted buckets with Object Lock on every copy, replicated to us-east-1 with Replication Time Control in prod; stage and dev keep one copy in eu-central-1. | test | `infra/modules/s3-backup` (`region_role` working or recovery, one RTC rule per destination); OPA `s3-object-lock-required`; `tests/s3-backup.tftest.hcl`. | D5, D7, ADR-0019 |
| FR-DAT-17 | MemoryDB shall not be replicated across regions; in prod its hourly snapshots shall be copied to us-east-1, and after a promotion the running us-east-1 MemoryDB shall warm from Aurora. | test | No multi-Region cluster in `infra/modules/memorydb`; copies by the `backup` plans; `infra/live/prod/us-east-1/{cell-*,spare}/memorydb`; warm-up gate `FR-DAT-24`. | D3, D7, ADR-0019 |
| FR-DAT-18 | In prod, Aurora of every cell, the spare and the locker shall have a Global Database secondary in us-east-1 with one instance of the writer class of its working cluster, and DynamoDB shall replicate there through Global Tables in MREC mode; stage and dev have no recovery-region replicas. | test | `recovery_regions` of `infra/modules/aurora-global` and `infra/modules/dynamodb-global`, asserted in their `tests/`; `standby` in `config/environments/prod.yaml`. | D7, ADR-0019 |
| FR-DAT-21 | The restore role, KMS key access and quotas used by a restore shall be the ones exercised by the daily test. | inspection | Restore testing plan of `infra/modules/backup`; `infra/modules/restore-automation`. | D4, D7, ADR-0019 |
| FR-OBS-11 | The region-loss detection signal shall fire when two of three independent probe points outside Frankfurt cannot reach it for 2 min, and a failing Route 53 health check shall alert after 3 min. | test | Alerts `RegionDown` (`probe_success` from `use1` in us-east-1 and the external providers `ext` and `ext2`) and `Route53HealthCheckFailing` in `observability/alerts/network/edge.yaml`; probe points in `observability/exporters/blackbox.yaml`. | D7, section 21.2, ADR-0019 |
| FR-OBS-24 | A full region switch of prod to the us-east-1 hot standby and back shall be tested every quarter as an announced game day with on-call approval, with the promotion as the only point of no return; stage tests only the component steps. | test | `tests/chaos/region-switch/scenario.json` validated by `runner.py --dry-run`; alert `DrSwitchTestOverdue`; dashboard `l3-data/dr-switch.json`. | D7, ADR-0019 |
| FR-POL-10 | An SCP shall deny every API call outside eu-central-1 and us-east-1, except global services. | test | `policy/scp/region-allow-list.json` (`DenyOutsideAllowedRegions`), attached by `infra/modules/org-policies`; `policy/scp/tests/test_scp.py`. | D6, D7, ADR-0019 |
| FR-POL-11 | An SCP shall deny DynamoDB writes in us-east-1 except by the replication service, and the promotion shall detach it. | test | `policy/scp/deny-dynamodb-writes-recovery-regions.json`; `scripts/dr/failover.py`; `policy/scp/tests/test_scp.py`. | D7, ADR-0019 |
| FR-SEC-24 | Secrets shall be kept in Vault or Secrets Manager, never in Git or Terraform state, and in prod Secrets Manager secrets shall be replicated to us-east-1. | test | `infra/modules/secrets-replica` (no secret version resource); External Secrets in `deploy/platform/external-secrets`; `gitleaks` in `make lint-secrets`. | Section 6 (secrets), section 23.6, ADR-0019 |
| NFR-REC-3 | On loss of the working region, prod service shall resume in us-east-1 within 60 min (RTO), on a timed critical path of 32 min: detection and confirmation 10, fencing 2, Aurora promotion 3, cache warm-up 15, traffic switch 2. | test | Quarterly game day `tests/chaos/region-switch/scenario.json` (`rto_target_min` 60), critical path printed by `runner.py scenario.json --dry-run`; alert `DrSwitchTestOverdue` after 100 days without a passed switch. | D7, ADR-0019 |
| NFR-REC-8 | In prod, the snapshot-only stores (MemoryDB, ClickHouse, Vault, Velero) shall have RPO 1 h on loss of the working region. | metric | Hourly backups of `infra/modules/backup` copied to us-east-1; alert `SnapshotCopyStale` (last copy older than 2 h). | D7, ADR-0019 |

## Withdrawn

| ID | Reason |
|---|---|
| FR-INF-14 | The second recovery region is removed (ADR-0019); us-east-1 is the only standby region. |
| NFR-REC-18 | Plan B is removed with the second recovery region; the hot standby needs no capacity at the switch (FR-INF-16). |
| NFR-REC-21 | The plan-B critical path is removed; NFR-REC-3 states the timed path of the switch to us-east-1. |
