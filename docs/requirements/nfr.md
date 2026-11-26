---
status: baseline
---

# Non-functional requirements

The only file that defines `NFR-` IDs. Error budget = (1 - SLO) x 43,200 minutes over 30 days.

## Load and capacity

| ID | Requirement | Verification | Implementation | Source |
|---|---|---|---|---|
| NFR-CAP-1 | The platform shall sustain the daily average of 160 TPS (about 1,100 router RPS, 13.8 million payments a day) within every SLO of this file. | test | k6 `tests/load/scenarios/average.js`, profile `average` in `tests/load/lib/profiles.js` (160 TPS, 1,100 RPS), thresholds from the SLOs in `tests/load/lib/options.js`. | Section 1 |
| NFR-CAP-2 | The platform shall sustain the daily peak of 480 TPS (about 3,300 router RPS) within every SLO of this file. | test | k6 `tests/load/scenarios/daily-peak.js`, profile `daily-peak` (480 TPS, 3,300 RPS, 30 min hold). | Section 1 |
| NFR-CAP-3 | The platform shall sustain the sale peak of 1,430 TPS (about 10,000 router RPS) within every SLO of this file. | test | k6 `tests/load/scenarios/sale-peak.js`, profile `sale-peak` (1,430 TPS, 10,000 RPS, 15 min hold); `spike.js` raises 3,300 to 10,000 RPS in 60 s. | Section 1, section 8 |
| NFR-CAP-4 | The platform shall pass a stress test at 2,860 TPS (20,000 router RPS) without platform-side 5xx above 0.1%. | test | k6 `tests/load/scenarios/stress.js` and `breakpoint.js`, profile `stress` (2,860 TPS, 20,000 RPS); abort on threshold breach (`abortOnFail`). | Section 1, section 8 |
| NFR-CAP-5 | Capacity planning shall use the per-payment load model of 7 router API calls, 50 database IOPS and 16 KB of stored data. | analysis | `CALLS_PER_PAYMENT = 7` and the request mix in `tests/load/lib/profiles.js`; Aurora and MemoryDB sizes in `config/environments/prod.yaml`. | Section 1 |
| NFR-CAP-6 | The platform shall hold 2,500 router RPS for 8 hours without memory growth of pods or MemoryDB. | test | k6 `tests/load/scenarios/soak.js` (profile `soak`, 28,800 s hold); memory alerts `MemoryDbMemoryCritical`, `PodOOMKilled`. | Section 8 |

## Service level objectives

| ID | Requirement | Verification | Implementation | Source |
|---|---|---|---|---|
| NFR-SLO-1 | Payment authorization (`POST /payments/{id}/confirm`) shall be answered without a platform-side 5xx for 99.99% of requests over 30 days (error budget 4.3 min); declines by the issuer and PSP errors correctly passed on or rerouted shall not count. | metric | `observability/slo/authorization-availability.yaml` (objective 99.99, `fault="platform"` filter), burn-rate alert `PaymentsAuthorizationAvailability`. | Section 1 |
| NFR-SLO-2 | Platform overhead over PSP time shall have p99 under 150 ms for 99.9% of requests over 30 days (error budget 43.2 min). | metric | `observability/slo/platform-overhead-latency.yaml`; k6 threshold `platform_overhead_ms`. | Section 1 |
| NFR-SLO-3 | Payment status read (`GET /payments/{id}`) shall have p99 under 50 ms without 5xx for 99.95% of requests over 30 days (error budget 21.6 min). | metric | `observability/slo/payment-status-read.yaml`; k6 threshold `http_req_duration{type:status}`. | Section 1 |
| NFR-SLO-4 | An outgoing merchant webhook shall be delivered within 60 s of its event for 99.9% of events; this SLO has no error budget. | metric | `observability/slo/merchant-webhook-delivery.yaml`; alert `WebhookBacklogOld` (oldest webhook older than 300 s for 10 min). | Section 1 |
| NFR-SLO-5 | The drain lag shall have p99 under 5 s, and an alert shall fire when a Redis stream holds more than 50,000 entries. | metric | Alerts `DrainLagHigh` (`drain_lag_seconds > 5` for 5 min) and `RedisStreamBacklog` (`redis_stream_length > 50000` for 5 min) in `observability/alerts/application/components.yaml`. | Section 2, section 13 |
| NFR-SLO-6 | The locker shall be available for 99.99% of requests over 30 days. | metric | Alert `LockerErrorRateHigh` (locker 5xx ratio above 1% for 5 min, critical); locker canary analysis on errors and p99. | Section 13 (ADR-013a) |

## Recovery

| ID | Requirement | Verification | Implementation | Source |
|---|---|---|---|---|
| NFR-REC-1 | Loss of one availability zone in Frankfurt shall lose no payment data (RPO 0) and restore service within 1 min (RTO). | test | FIS `tests/chaos/fis/az-loss.json` (network disruption of one AZ); MemoryDB transaction log in 3 AZs, Aurora quorum and reader promotion, pod spread per AZ. | Section 1 |
| NFR-REC-2 | On loss of the working region the payment data RPO shall be at most 10 s of Aurora replication plus the undrained entries within the drain lag (p99 5 s). | metric | Alerts `AuroraGlobalLagHigh` (above 5,000 ms for 2 min) and `AuroraGlobalLagRpoBudgetExceeded` (above 10,000 ms) in `observability/alerts/backup-dr/replication.yaml`. | D7 |
| NFR-REC-3 | On loss of the working region service shall resume in the recovery region within 60 min (RTO), and within 75 min in plan B (us-east-2). | test | Quarterly switch `tests/chaos/region-switch/scenario.json` (rto_target_min 60) and `plan-b.json` (75); alert `DrSwitchTestOverdue` after 100 days without a passed switch. | D7 |
| NFR-REC-4 | The locker data shall have RPO 10 s and RTO 60 min on loss of the working region. | test | Locker Aurora global cluster in `infra/live/<env>/<region>/locker/aurora`; promoted by `scripts/dr/failover.py` together with the cells. | D7 |
| NFR-REC-5 | The merchant-to-cell map in DynamoDB shall have an RPO of about 1 s on loss of the working region. | metric | DynamoDB Global Tables MREC; alert `DynamoDbGlobalTableLagHigh` (replication latency above 5,000 ms for 10 min). | D7 |
| NFR-REC-6 | S3 objects (backups, audit logs, Terraform state, event archive) shall have RPO 15 min plus the S3 sink flush interval. | metric | Replication Time Control (15 min) in `infra/modules/s3-backup`; alert `S3ReplicationLagHigh` (above 900 s for 10 min). | D7 |
| NFR-REC-7 | ClickHouse shall have RPO 15 min and RTO 4 h, restored from its hourly backup and caught up from the event archive. | test | `infra/modules/clickhouse` validates `rpo_minutes <= 15` and `rto_hours <= 4`; hourly `clickhouse-backup` CronJob. | Section 1, D3, section 21.3 |
| NFR-REC-8 | The snapshot-only stores (MemoryDB, ClickHouse, Vault, Velero) shall have RPO 1 h on loss of the working region. | metric | Hourly backups of `infra/modules/backup` copied to us-east-1 and us-east-2; alert `SnapshotCopyStale` (last copy older than 2 h). | D7 |
| NFR-REC-9 | Kubernetes manifests shall have RPO 0 (Git is the source) and cluster objects RPO 1 h. | inspection | Argo CD renders every manifest from `deploy/` in Git (`deploy/argocd/templates/`); cluster-object backups are tracked per store by `BackupMissing` and `SnapshotCopyStale`. | Section 1, D3 |
| NFR-REC-10 | The PSP reconciliation window after a promotion shall be 5 minutes, sized to the payment-data RPO plus a margin, and one hour only in the snapshot-copy fallback. | test | `RECONCILE_WINDOW_MINUTES = 5` in `scripts/dr/failover.py` (log event `reconcile-window`), `scripts/dr/tests/test_failover.py`; alert `OrphanPaymentWebhooks`. | D7 |
| NFR-REC-11 | Restore of an application database (Aurora of a cell or the locker, DynamoDB) shall lose at most 5 min of data, to any second in the 35-day retention. | metric | Continuous backup and PITR 35 days (`aurora-global`, `dynamodb-global`, `backup`); alert `LatestRestorableTimeLagHigh` (lag above 5 min for 10 min). | D2 |
| NFR-REC-12 | Restore of an application database in Frankfurt after a logical error shall take at most 30 min into prepared capacity, with an alert at 80% of the target. | metric | `RestoreTargetSeconds` 1800 in `infra/modules/restore-automation`; alerts `RestoreDurationNearTarget` (above 0.8 of target) and `RestoreTooSlow`. | D4 |
| NFR-REC-13 | The restore of every application database shall be verified automatically every day. | metric | Daily restore testing of the `gold` plan in `infra/modules/backup`; alerts `RestoreTestFailed` and `RestoreTestStale` (no run for 2 days). | D2 |
| NFR-REC-14 | MemoryDB, ClickHouse and Velero shall be backed up every hour with retention 35 days; pre-migration snapshots shall be kept 35 days. | test | `gold` and `silver` plans (hourly, 35 days) in `infra/modules/backup/tests`; `SNAPSHOT_RETENTION_DAYS=35` enforced by Kyverno `require-migration-snapshot`. | D3 |
| NFR-REC-15 | Object backups shall move to a colder tier after 7 days and a still colder tier after 14 days, and the monthly archive shall be kept 7 years in the coldest tier. | test | Lifecycle of `infra/modules/s3-backup`: Glacier Instant Retrieval at 7 days, Glacier at 14, expiry at 35; `archive/monthly/` to Deep Archive for 7 years; asserted in its `tests/`. | D5 |
| NFR-REC-16 | After a node replacement, AZ loss or recovery a cell shall take traffic once 75% of the priority hot keys are warm, and after at most 5 min in any case with a non-paging alert. | test | Router values `warmup.minRatio: 0.75`, `maxWaitSeconds: 300`; alert `CacheWarmRatioLow` (`cache_warm_ratio < 0.75`, warning); steady state S5 of the region switch. | D8 |
| NFR-REC-17 | Aurora Global Database replication lag shall alert at 5 s, the RPO budget shall be 10 s, and managed RPO (`rds.global_db_rpo`) shall stay off. | test | `infra/modules/aurora-global` never sets `rds.global_db_rpo`; alerts `AuroraGlobalLagHigh` and `AuroraGlobalLagRpoBudgetExceeded`; `observability/tests/backup-dr/replication.test.yaml`. | D7 |
| NFR-REC-18 | Plan B in us-east-2 shall start after 10 minutes without capacity in us-east-1. | test | Step `wait-capacity-us-east-1` (10 min) in `tests/chaos/region-switch/plan-b.json`, validated by `runner.py --dry-run`. | D7 |
| NFR-REC-21 | The plan-B critical path shall fit 75 min with these budgets: detection and confirmation 10, fencing 2, waiting for capacity in us-east-1 10, then in parallel Aurora promotion 3 with instances 12, MemoryDB 15 and EKS with base components 25, cell sync with warm-up 15, traffic switch 2 (critical path 64 min). | test | Step `budget_min` values and the step DAG of `tests/chaos/region-switch/plan-b.json`, critical path printed by `runner.py plan-b.json --dry-run`. | D7 |
| NFR-REC-19 | Promotion of the us-east-1 standby data stores shall start after 5 consecutive one-minute periods of a failing working-region health check, never on missing data. | test | `alarm_evaluation_periods = 5` (range 3 to 30) and missing data not breaching in `infra/modules/dr-failover`; `infra/modules/dr-failover/tests/dr-failover.tftest.hcl`. | ADR-0017 |
| NFR-REC-20 | Failback to Frankfurt shall refuse to run while the replication lag to Frankfurt exceeds 1 s. | test | `MAX_FAILBACK_LAG_MS = 1000` in `scripts/dr/failover.py`; `scripts/dr/tests/test_failover.py`. | ADR-0017 |

## Cost

| ID | Requirement | Verification | Implementation | Source |
|---|---|---|---|---|
| NFR-COST-1 | A change that raises the estimated monthly cost by more than 1,000 USD shall need FinOps approval before merge. | inspection | Infracost estimate of the changed `infra/live/**` stacks in the pull request, approved by the FinOps owner. | Section 12, section 20.9 |
| NFR-COST-2 | AWS Budgets shall alert at 80% and 100% of each budget. | test | `aws_budgets_budget` notifications at 80 and 100 PERCENTAGE (pattern of `infra/modules/bedrock-access`); panel `finops: budget used` in `observability/dashboards/finops/cost.json`. | Section 12 |
| NFR-COST-3 | Reservation utilization shall stay above 95%, reservation and Savings Plan coverage of steady compute shall be 70 to 80%, and the Savings Plan commitment shall be 80% of the minimum hourly compute. | analysis | Cost Explorer utilization and coverage reports; spend per component on `observability/dashboards/finops/cost.json`. | Section 12 |

## Alert coverage

| ID | Requirement | Verification | Implementation | Source |
|---|---|---|---|---|
| NFR-COV-1 | Alert coverage of the failure-mode catalog shall be at least 90% for the data, application, security-PCI and backup-DR layers and at least 80% for every other layer. | test | `observability/coverage/targets.yaml` (data, application, security-pci, backup-dr 0.9; default, network, compute 0.8); `observability/coverage/alert_coverage.py` and `tests/test_coverage.py`. | Section 25.2 |
| NFR-COV-2 | Fire-drill coverage shall be at least 60% of the failure modes of each layer and 100% of the modes with severity `critical`. | metric | `detect_within` per mode in `observability/coverage/catalog/*.yaml` (asserted by `observability/tests/test_contract.py`); FIS and Chaos Mesh experiments in `tests/chaos/`. | Section 25.4 |
| NFR-COV-3 | Every alert shall have a unit test that fires on the condition and stays silent without it, and a runbook with diagnostic steps. | test | `promtool test rules` over `observability/tests/<layer>/*.test.yaml` run by `observability/tests/run.py`; `runbook_url` to `docs/runbooks/<layer>/` checked by `observability/tests/test_contract.py`. | Section 25.3, section 25.4 |
