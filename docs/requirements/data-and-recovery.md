---
status: baseline
---

# Data and recovery requirements

Data stores, the write path, backups, restore, resilience and cache warm-up. Numbers are in `nfr.md` (`NFR-REC-*`, `NFR-SLO-5`); the region model is ADR-0017.

## Data stores and write path

| ID | Requirement | Verification | Implementation | Source |
|---|---|---|---|---|
| FR-DAT-1 | The router shall keep payment state in MemoryDB and a Redis stream, and the drainer shall write it to Aurora in batches; the router shall never write PostgreSQL on the hot path. | metric | Write-behind of Hyperswitch (router, drainer); `DrainLagHigh` and `RedisStreamBacklog` alerts hold `NFR-SLO-5`; drainer stall experiment `tests/chaos/chaos-mesh/drainer-stall.yaml`. | Section 2 (write path), ADR-002 |
| FR-DAT-2 | MemoryDB of each cell shall run 2 shards of 1 primary and 2 replicas over three AZs with TLS, ACL users and `maxmemory-policy noeviction`. | test | `infra/modules/memorydb` and its `tests/`; alerts `MemoryDbMemoryCritical` (above 85%) and `MemoryDbEvictions`. | Section 5, ADR-002 |
| FR-DAT-3 | Aurora PostgreSQL 16 of every cell and of the locker shall use an I/O-Optimized writer, readers, RDS Proxy, forced TLS 1.3, `pg_stat_statements` and pgaudit. | test | `infra/modules/aurora-global` parameter groups and proxy; `infra/modules/aurora-global/tests/aurora-global.tftest.hcl`. | Section 5 (PostgreSQL), ADR-003 |
| FR-DAT-4 | MSK shall run 9 brokers over three AZs with replication factor 3, `min.insync.replicas=2`, IAM authentication only, TLS and topic auto-creation off. | test | `infra/modules/msk` and its `tests/`; alerts `KafkaUnderReplicatedPartitions`, `KafkaConsumerLagHigh`, `KafkaBrokerDiskHigh`. | Section 5, section 20.2 |
| FR-DAT-5 | The payment path shall accept payments without MSK, and events shall reach the S3 event archive through the S3 sink so that Kafka and ClickHouse can be rebuilt from it. | inspection | `sink_role_arn` and `sink_bucket_policy_statements` of `infra/modules/msk`; archive bucket `s3-event-archive` of `infra/modules/s3-backup`. | D7 |
| FR-DAT-6 | A PSP authorization shall never be retried automatically; a PSP timeout (15 s) shall put the payment in the unknown state, resolved by sync. | test | `psp-authorize` with `max_attempts: 0` and `timeout: 15s` in `policy/resilience/policy.yaml`, checked by `policy/resilience/validate.py` and `tests/test_validate.py`; alert `UnknownStatePaymentsStale`. | Section 2 (PSP), section 24.2, section 24.3 |
| FR-DAT-7 | Every dependency call shall have a timeout, capped exponential backoff with full jitter, a 10% retry budget and a 30 s request deadline that propagates. | test | `defaults` and `dependencies` of `policy/resilience/policy.yaml` (psp-sync 5 s x 4, router-locker 300 ms x 2, memorydb 50 ms x 2, aurora 2 s x 2), validated against `policy/resilience/schema.json`. | Section 24.1, section 24.2 |
| FR-DAT-8 | Retry storms and exhausted retry budgets shall alert, critical for `psp-sync` and `router-locker`. | test | Alerts `RetryStorm`, `RetryBudgetExhausted`, `RetryBudgetExhaustedNonCritical` in `observability/alerts/application/resilience.yaml` with tests in `observability/tests/application/`. | Section 24.5 |
| FR-DAT-9 | The mesh shall add no transport retry on the payment routes, and every service shall have a connection pool limit and outlier detection. | test | Envoy `retry_policy` with empty `retry_on` in `deploy/charts/payments-edge/templates/envoyfilter.yaml`; `connectionPool` and `outlierDetection` of `platform-common` `_destinationrule.tpl`; Chaos Mesh `psp-timeout.yaml`. | Section 24.4 |
| FR-DAT-10 | During a partition the platform shall prefer consistency of payment state: Frankfurt alone writes, recovery regions are read-only replicas until a promotion. | analysis | Single writer (FR-INF-12); DynamoDB write deny in recovery regions; Aurora secondaries read-only until `failover-global-cluster`. | Section 2 (CAP and PACELC), D6 |

## Backups and retention

| ID | Requirement | Verification | Implementation | Source |
|---|---|---|---|---|
| FR-DAT-11 | Every stateful resource shall join an AWS Backup plan by its `backup-tier` tag: gold hourly 35 days with copies to us-east-1 and us-east-2, continuous 35 days and monthly 7 years; silver hourly 35 days with copies; bronze daily 7 days. | test | `infra/modules/backup` and `infra/modules/backup/tests/backup.tftest.hcl`; OPA `policy/opa/terraform/backup-tier-required`. | D2, D3, section 19, section 21.5 |
| FR-DAT-12 | Aurora and DynamoDB shall keep point-in-time recovery for 35 days in the working region. | test | `backup_retention_days = 35` in `_envcommon/data/aurora.hcl`; PITR on the table and every replica in `infra/modules/dynamodb-global`; OPA `no-stateful-without-backup`. | D2 |
| FR-DAT-13 | Backup vaults shall be encrypted with backup-account keys, locked in compliance mode (7 to 2,555 days) and admit only copy-in from the source accounts. | test | Vault Lock and vault policy of `infra/modules/backup`; alert `BackupVaultPolicyChanged`. | Section 19, section 6 |
| FR-DAT-14 | Object backups, audit logs, the event archive and Terraform state shall be kept in versioned KMS-encrypted buckets with Object Lock on every copy, replicated to us-east-1 and us-east-2 with Replication Time Control. | test | `infra/modules/s3-backup` (`region_role` working or recovery, one RTC rule per destination); OPA `s3-object-lock-required`; `tests/s3-backup.tftest.hcl`. | D5, D7 |
| FR-DAT-15 | Self-managed backups (ClickHouse, Vault, OpenSearch) shall be compressed with zstd at a low level before encryption and written over S3 VPC endpoints. | test | `clickhouse-backup` hourly with zstd level 1 in `infra/modules/clickhouse` and its `tests/`; Vault Raft snapshot CronJob in `deploy/platform/vault/config`; OpenSearch Snapshot Management to `s3-backup`. | D4 |
| FR-DAT-16 | A failed backup job, a failed copy, a missing backup and a stale snapshot copy shall each raise an alert. | test | `BackupJobFailed`, `BackupCopyFailed`, `BackupMissing` (twice the interval), `SnapshotCopyStale` (2 h) in `observability/alerts/backup-dr/backups.yaml`; tests in `observability/tests/backup-dr/backups.test.yaml`. | Section 19 (monitoring) |
| FR-DAT-17 | MemoryDB shall not be replicated across regions; its hourly snapshots shall be copied to both recovery regions and the store rebuilt from Aurora at a switch. | test | No multi-Region cluster in `infra/modules/memorydb`; copies by the `backup` plans; warm-up gate `FR-DAT-24`. | D3, D7 |
| FR-DAT-18 | Aurora of every cell and the locker shall have headless Global Database secondaries in us-east-2 and secondaries in us-east-1, and DynamoDB shall replicate to both through Global Tables in MREC mode. | test | `recovery_regions` of `infra/modules/aurora-global` and `infra/modules/dynamodb-global`, asserted in their `tests/`. | D7 |

## Restore

| ID | Requirement | Verification | Implementation | Source |
|---|---|---|---|---|
| FR-DAT-19 | Restore shall be code: an SSM Automation document and Terraform, with no manual step except the approval of its pull request. | test | `infra/modules/restore-automation` (SSM document, EventBridge trigger) and its `tests/`; runbooks `docs/runbooks/backup-dr/`. | D4, section 19 |
| FR-DAT-20 | The daily restore test shall restore each gold Aurora cluster and DynamoDB table, warm the restored PostgreSQL with `pg_prewarm`, check row counts and checksums, and publish duration, target and success per store. | metric | `RestoreDurationSeconds`, `RestoreTargetSeconds`, `RestoreSuccess` of `infra/modules/restore-automation` exported as `backup_restore_*`; alerts in `observability/alerts/backup-dr/restore.yaml`. | D2, D4 |
| FR-DAT-21 | The restore role, KMS key access and quotas used by a restore shall be the ones exercised by the daily test, and the test shall also run in us-east-2. | inspection | `infra/live/prod/us-east-2/restore-test`; restore testing plan of `infra/modules/backup`. | D4, D7 |
| FR-DAT-22 | Before every migration or schema change of Aurora, DynamoDB, ClickHouse or OpenSearch, the migration Job shall take an on-demand snapshot labelled with the change and start the change only when the snapshot is available. | test | Init container `scripts/schema/pre-migration-snapshot.sh` (exit 0 only when available) with `scripts/schema/tests`; Kyverno `policy/kyverno/require-migration-snapshot`. | D3 |
| FR-DAT-23 | Migrations shall be expand-contract only and `down.sql` shall never run in prod. | test | `tools/ci/migrations/migration_check.py` (structure, destructive statements), squawk and `migration_roundtrip.sh` (up, down, up) in the `migrations` job of `.github/workflows/ci.yml`; chart `deploy/charts/migrations`. | Section 5 (migrations), section 17 |

## Warm-up and recovery of a cell

| ID | Requirement | Verification | Implementation | Source |
|---|---|---|---|---|
| FR-DAT-24 | The readiness of a router pod shall wait for the cache warm-up of priority hot keys (merchant configuration, routing, limits) up to the ratio and time of `NFR-REC-16`. | test | `warmup` values of `deploy/charts/router/values.yaml` behind the `/health/deep` check; chart tests in `deploy/charts/router/tests/`; alert `CacheWarmRatioLow`. | D8 |
| FR-DAT-25 | Writes to DynamoDB in the recovery regions shall be denied until a promotion removes that region from the deny list. | test | `deny_recovery_writes` policy of `infra/modules/dynamodb-global` attached to every workload role by `infra/modules/iam-workloads`; removed per region by `scripts/dr/failover.py`. | D7 |
| FR-DAT-26 | Promotion shall fence the working region where it still answers by a drop rule in its `psp-fence` Network Firewall rule group before the Aurora global failover. | test | `FENCE_RULE` (`sid:900001`) in `scripts/dr/failover.py`; `fence_rule_group` of `_envcommon/data/dr-failover.hcl`; `scripts/dr/tests/test_failover.py`. | D6, ADR-0017 |
| FR-DAT-27 | Payments charged at the PSP in the reconciliation window of `NFR-REC-10` and missing after a promotion shall be found and refunded by people; the write-behind rule stays. | metric | Alert `OrphanPaymentWebhooks` (PSP webhooks for unknown payments) and `ReconciliationMismatch`; runbook `docs/runbooks/meta/promote-standby-region.md`. | D7 |
