# Data stores

Every database and store of the platform: what it holds, who writes and reads it, how consistent it is, how long data stays, how it is backed up and restored, which KMS key encrypts it and how big it is in each environment. Sizes come from `config/environments/<env>.yaml` and the defaults in `infra/live/<env>/env.hcl`, which is what Terraform reads. The backup mechanics shared by all stores are in [data stores and backups](../foundation/data-backups.md).

## Summary

| Store | Scope | Data class tag | `pci-scope` tag | Backup tier tag | KMS key |
|---|---|---|---|---|---|
| [MemoryDB](#memorydb) | one per cell | `pii` | `cde` | `silver` | cell key (`cell-0` ... `spare`) |
| [Cell Aurora](#cell-aurora) | one per cell | `card-data` | `cde` | `gold` | cell key |
| [Locker Aurora](#locker-aurora) | one per region, shared by all cells | `card-data` | `cde` | `gold` | `locker` |
| [DynamoDB cell map](#dynamodb-cell-map) | one global table | `internal` | `cde` | `gold` | `shared` |
| [S3 buckets](#s3-buckets) | per environment, replicated | `card-data` | `cde` | `gold` | `shared` |
| [MSK](#msk) | analytics, working region only | `internal` | `out-of-scope` | `none` | `shared` (data), `logs` (broker logs) |
| [ClickHouse](#clickhouse) | analytics cluster | `internal` | `out-of-scope` | `silver` | `shared` (backups) |
| [OpenSearch](#opensearch) | one central domain in shared-services | `internal` | `out-of-scope` | `bronze` | `shared` key of shared-services (data), `logs` key (domain log groups) |
| [Vault](#vault) | one HA cluster in shared-services for every environment | `internal` | `cde` | `silver` | `<prefix>-shared-services-euc1-vault-unseal` |
| [Secrets Manager](#secrets-manager) | per account, replicated | `internal` | `cde` | `silver` | `shared` |
| [Rate limit Redis](#rate-limit-redis) | edge cluster | not tagged in the repo | not tagged | not tagged | not set in the repo |

The KMS keys come from the `kms` stack of each region (`infra/live/<env>/<region>/kms`): one key per cell, plus `locker`, `shared`, `logs`, `backup` and `ebs-nodes`. In prod each has a replica in us-east-1 under the same name; dev and stage replicate only the `logs` key there, for the edge.

Tags are set in `infra/live/_envcommon/<area>/<store>.hcl`; the allowed values are in `policy/tagging/schema.yaml`.

## MemoryDB

**What it holds.** The hot state of one cell, in the Redis OSS API:

- payment state that the router writes on the hot path;
- the drainer streams `{shard_0}_drainer_stream` to `{shard_63}_drainer_stream` (`global.hyperswitch.drainer.numPartitions: 64`);
- the scheduler stream `SCHEDULER_STREAM` and its consumer group `SCHEDULER_GROUP`;
- ephemeral keys (`epk_`) and the router's caches.

Data class `pii`: payment records carry customer fields, never a PAN.

**Writers and readers.**

| Service | ACL user | Access |
|---|---|---|
| router | `<cell>-router` | writes state, appends to the drainer stream |
| drainer | `<cell>-drainer` | reads the drainer streams and trims what it has written |
| scheduler | `<cell>-scheduler` | producer writes `SCHEDULER_STREAM`, consumer reads it |

Passwords are in Vault at `secret/<env>/<cell>/<service>/redis`. ACL string per user: `on ~* &* +@all -@admin -@dangerous` (`infra/live/<env>/env.hcl`).

**Consistency.** One primary per shard. A write is acknowledged only after the multi-AZ transaction log has it, so losing a node or a zone loses no acknowledged write. `maxmemory-policy noeviction`: when memory is full, writes fail instead of dropping stream entries.

**Retention.** Keys live as long as Hyperswitch sets their TTL; stream entries stay until the drainer has written them to Aurora and trims the stream.

**Backup and restore.**

- Native snapshots daily, kept 35 days.
- Hourly snapshots through AWS Backup (`backup-tier` tag), kept 35 days and copied to us-east-1 in prod.
- Not replicated across regions. The prod cells in us-east-1 run their own MemoryDB at full size; at a switch it is warmed from Aurora before the cell takes traffic.

**Encryption.** The cell key (`key_arns["<cell>"]` in `infra/live/<env>/eu-central-1/<cell>/memorydb`). TLS in transit.

**Size.**

| Environment | Node type | Shards | Replicas per shard |
|---|---|---|---|
| prod | `db.r7g.xlarge` | 2 | 2 |
| stage | `db.r7g.xlarge` | 2 | 2 |
| dev | `db.t4g.small` | 1 | 2 |

The module accepts only `num_replicas_per_shard = 2`.

## Cell Aurora

**What it holds.** The system of record of one cell: Aurora PostgreSQL 16, database `hyperswitch`, schema `public`. Payments, payment attempts, refunds, disputes, merchant accounts, profiles, merchant connector accounts (PSP credentials encrypted by the router), hashed API keys, and the `process_tracker` table of scheduler tasks. No PAN: card fields are locker tokens. The tag is `card-data` because the cluster is inside the CDE.

**Writers and readers.**

| Who | Login | Path | Access |
|---|---|---|---|
| drainer | `hs_app` | RDS Proxy | writes the payment rows from the stream in batches (write-behind) |
| router | `hs_app` | RDS Proxy | reads payments; writes configuration (merchants, keys, connector accounts) |
| scheduler | `hs_app` | RDS Proxy | reads and updates `process_tracker` and payments |
| migrations Job | `hs_migrator` | writer endpoint, IAM auth | DDL only |

All three services share the login `hs_app`; its password is in Vault at `secret/<env>/<cell>/{router,drainer,scheduler}/database` (one value in three paths) and in Secrets Manager at `<cluster name>/proxy/hs_app` for the proxy.

**Consistency.** One writer. Readers and the cross-region secondaries are asynchronous; an alarm fires when a secondary lags more than 5 s. The proxy has no read-only endpoint, so replica reads use the proxy too (`deploy/envs/<env>/<region>/<cell>/values.yaml`). TLS only (`rds.force_ssl`, TLS 1.3), clients use `verify-full`.

**Retention.** Rows are kept indefinitely; there is no purge job in the repo. Backups below.

**Backup and restore.**

- Continuous backup with point-in-time recovery for 35 days (`backup_retention_days = 35`).
- Hourly snapshots, copied to us-east-1 in prod; a monthly copy is kept 7 years.
- A snapshot before every schema change, taken by the [migrations Job](migrations.md).
- Aurora Global Database (prod): a secondary cluster in us-east-1 with one running instance of the writer class, which the switch promotes.
- A daily restore test restores the cluster and runs a validator (`RestoreSuccess`, `RestoreDurationSeconds`).

**Encryption.** The cell key (`key_arns["<cell>"]` in `infra/live/<env>/eu-central-1/<cell>/aurora`).

**Size.**

| Environment | Writer | Readers | Hot standby in us-east-1 |
|---|---|---|---|
| prod | `db.r7g.12xlarge`, I/O-Optimized | 1 x `db.r7g.4xlarge` | 1 x `db.r7g.12xlarge` |
| stage | dev sizes; prod sizes in a `prod-size` window | as dev; as prod in the window | none |
| dev | `db.r7g.large` | 0 | none |

The `spare` cell uses `db.r7g.2xlarge` for its writer, reader and us-east-1 instance.

## Locker Aurora

**What it holds.** The card vault database `locker`: encrypted cards and other vaulted data (tables `merchant`, `locker`, `hash_table`, `fingerprint`, `vault`, `entity`, `reverse_lookup` from `vendor/card-vault/migrations`). This is the only database that holds a PAN, always encrypted by the locker before it is written.

**Writers and readers.** Only the [locker](locker.md), login `locker_app` through RDS Proxy. Only the `locker_pod` security group reaches the proxy. The DDL runs in the `locker-migrations` Job against the writer endpoint.

**Consistency.** As for the cell Aurora: one writer, asynchronous readers and secondaries.

**Retention.** Records stay until the router deletes them through the locker API; the locker table has a TTL column (`add-ttl-to-locker-table` migration).

**Backup and restore.** As for the cell Aurora: 35-day point-in-time recovery, hourly snapshots copied to us-east-1 in prod, 7-year monthly copy, Global Database secondary in us-east-1.

**Encryption.** Two layers. Aurora storage uses the `locker` KMS key (`infra/live/<env>/eu-central-1/locker/aurora`). Inside the rows, the locker encrypts each card with the per-tenant master key, which is itself KMS ciphertext under `alias/pay-<env>-<region-short>-locker`. Only the locker role may use that key.

**Size.** prod: `db.r7g.4xlarge` writer, readers as the cells, Standard storage, and 1 x `db.r7g.4xlarge` in us-east-1. dev and scheduled stage: `db.r7g.large`.

## DynamoDB cell map

**What it holds.** The map `merchant_id -> cell`, table `pay-<env>-euc1-merchant-cell-map` (module default `component = "merchant-cell-map"`, hash key `merchant_id`). Data class `internal`.

**Writers and readers.**

- Written by `scripts/cells/migrate-merchant.py` when a merchant moves between cells: it freezes the merchant's row, copies the data, then switches the `cell` attribute.
- Read access is granted to the router and scheduler roles of every cell (`dynamodb:GetItem`, `BatchGetItem`, `Query` in `infra/modules/iam-workloads`).
- Writes outside Frankfurt are denied by the `deny-recovery-writes` IAM policy attached to every workload role, until a region switch shrinks it.

**Consistency.** In prod, a global table with an MREC replica in us-east-1: eventually consistent across regions, with a replication-latency alarm. The migration script reads with `ConsistentRead=True` in Frankfurt.

**Retention.** Indefinite. Streams on (`NEW_AND_OLD_IMAGES`), on-demand capacity.

**Backup and restore.** Point-in-time recovery for 35 days on the table and every replica, hourly AWS Backup snapshots, and a daily restore test.

**Encryption.** `shared` key of each region it lives in (`infra/live/<env>/eu-central-1/dynamodb`).

**Size.** On-demand; no capacity is set in the repo.

## S3 buckets

The backup and event-archive buckets use `infra/modules/s3-backup`: versioning, Object Lock on every copy, KMS encryption, and in prod replication to us-east-1 with Replication Time Control (15 minutes) and a latency alarm.

| Bucket | Holds | Written by | Read by |
|---|---|---|---|
| `pay-<env>-euc1-backup` | object backups, ClickHouse backups, audit logs | AWS Backup, `clickhouse-backup` CronJob | restore jobs |
| `pay-<env>-euc1-event-archive` | MSK events under prefix `events/` | the MSK S3 sink (role `<msk name>-s3-sink`) | ClickHouse restore (read only), Kafka rebuild |
| `<prefix>-shared-services-euc1-vault-snapshots` | hourly Vault Raft snapshots | `vault-snapshot` CronJob | Vault restore |
| `<prefix>-<root>-euc1-tf-state-<account>`, one per state root, replicated to `<prefix>-<root>-use1-tf-state-<account>` | Terraform state | CI apply roles | CI plan and apply roles; the replica with `PAY_STATE_REGION=us-east-1` |

**Retention.** Lifecycle for the listed prefixes: Glacier Instant Retrieval at 7 days, Glacier at 14, expiry at 35. `archive/monthly/` moves to Deep Archive and expires after 7 years.

**Backup and restore.** The buckets are the backups. Object Lock prevents deletion before expiry; restore is a copy back from the replica or a previous version.

**Encryption.** `shared` key per region for the backup and event-archive buckets.

**Size.** Not sized in the repo.

## MSK

**What it holds.** Payment events for analytics. The cluster settings are in `infra/modules/msk`. The topics watched by the Kafka exporter are `payment-events`, `payment-dlq` and `audit-events` (`observability/exporters/kafka.yaml`). Topic auto-creation is off.

**Writers and readers.**

- Producers: the router and scheduler roles get `producer_policy_arn` (connect, describe, write; never read).
- Consumers: ClickHouse (Kafka engine) and the S3 sink to the event archive.
- Brokers accept IAM-authenticated TLS on port 9098 from the cell node security groups and the analytics nodes only (`infra/live/<env>/eu-central-1/analytics/msk-access`).

**Consistency.** Replication factor 3, `min.insync.replicas=2`: a write survives the loss of one broker.

**Retention.** 168 hours (7 days) on the brokers (`retention_hours`); older events live in the event archive.

**Backup and restore.** Not replicated across regions and not backed up (`backup-tier = none`). Kafka is rebuilt from the S3 event archive.

**Encryption.** `shared` key for data, `logs` key for broker logs in `/aws/msk/<name>`. TLS in transit and between brokers.

**Size.**

| Environment | Brokers | Instance | Volume per broker |
|---|---|---|---|
| prod | 3 | `kafka.m7g.large` | 1,000 GB |
| stage | 3 | `kafka.m7g.large` | 500 GB |
| dev | 3 | `kafka.m7g.large` | 100 GB |

## ClickHouse

**What it holds.** The analytics tables: payment, refund and dispute events for dashboards and reports. Self-managed on the analytics EKS cluster, namespace `clickhouse`, outside the CDE.

**Writers and readers.** Written by its Kafka engine from MSK; read by analytics queries. See [analytics consumers](analytics-consumers.md).

**Consistency.** Replicated tables over Keeper; replicas converge asynchronously (`ClickHouseReplicationLag` fires above 300 s).

**Retention.** Table TTLs are not set in the repo.

**Backup and restore.**

- `clickhouse-backup` CronJob every hour, zstd level 1, into the backup bucket, kept 35 days.
- Restore loads the latest backup, then replays the event archive after it. The backup role cannot delete backups.
- Targets: RPO 15 minutes, RTO 4 hours (validated in `infra/modules/clickhouse`). Alarms on a missing backup, on a restore above 80% of the RTO, and on archive catch-up lag above the RPO.

**Encryption.** Backups and the archive under the `shared` key.

**Size.**

| Environment | Shards x replicas | Node | Keeper |
|---|---|---|---|
| prod | 2 x 2 | `r7g.2xlarge` | 3 nodes |
| stage | as dev; as prod in a `prod-size` window | | |
| dev | 1 x 1 | stateful pool, 16 vCPU cap | not stated |

## OpenSearch

**What it holds.** The application logs of every environment (data streams `logs-app-<env>`) and the audit trail (`logs-audit`: CloudTrail and EKS audit from the log archive bucket), in one domain `pay-shared-euc1-logs` in shared-services (`infra/modules/opensearch`). No card data: the collector and Logstash both mask PANs.

**Writers and readers.** Logstash writes `logs-app-<env>` with its IRSA role; OpenSearch Ingestion writes `logs-audit`. People read through OpenSearch Dashboards (`logs.payments.internal`, Okta) and Grafana; the admin AI agent of each environment reads only `logs-app-<env>` through the VPC endpoint of its environment. Fine-grained access control maps each Okta group to a role (`infra/modules/opensearch-indices`).

**Consistency.** Dedicated masters, hot data nodes over three zones, 1 replica per shard.

**Retention.** `logs-app-<env>`: hot 7 days, UltraWarm until day 30, then deleted. `logs-audit`: hot 30 days, UltraWarm until day 365. The log archive bucket stays the source of truth for the audit trail.

**Encryption.** KMS at rest, node-to-node TLS, TLS 1.2 minimum, VPC only.

**Size and operations.** Shards, rollover and the commands to inspect them are on the [Logging](../runtime/logging.md) page.

## Vault

**What it holds.** Application secrets in KV v2 under `secret/` (`max_versions` 10). Paths:

| Path | Fields | Read by |
|---|---|---|
| `secret/<env>/<cell>/router/{database,redis}` | `password` | router |
| `secret/<env>/<cell>/drainer/{database,redis}` | `password` | drainer |
| `secret/<env>/<cell>/scheduler/{database,redis}` | `password` | scheduler |
| `secret/<env>/<cell>/shared/app` | `master_enc_key`, `admin_api_key`, `jwt_secret`, `api_keys_hash_key`, `user_auth_encryption_key` | router, scheduler |
| `secret/<env>/<cell>/shared/locker` | `vault_encryption_key`, `vault_private_key`, `tunnel_private_key` | router, scheduler |
| `secret/<env>/locker/database` | `password` | locker |
| `secret/<env>/locker/jwe` | `locker-private-key` | locker |
| `secret/<env>/locker/tenants/<id>` | `master-key`, `public-key` | locker |

**Writers and readers.** Operators write values through Vault only, never Git. External Secrets Operator of each cluster reads them through the jwt auth mount of its cluster, `k8s-<cluster name>`, role `external-secrets`, with policy `pay-<env>-external-secrets` (read `secret/data/<env>/*`, so a cluster reads only its own environment); per-service roles `<cell>-<service>` with policies `pay-<env>-<cell>-<service>` limit each cell service to its own paths.

**Consistency.** Raft, 3 pods, one per zone, Raft autopilot with a minimum quorum of 3.

**Retention.** 10 versions per key.

**Backup and restore.** Hourly Raft snapshots to the vault-snapshots bucket of shared-services, replicated to us-east-1. Recovery keys (5 shares, threshold 3) are in Secrets Manager at `<prefix>/shared-services/vault/init`.

**Encryption.** Auto-unseal with `alias/<prefix>-shared-services-euc1-vault-unseal`.

**Placement and size.** One Vault on the central cluster of shared-services serves every environment; every cluster reaches it at `vault.host` (`https://vault.payments.internal`, port 443 of the internal admin gateway) through the transit gateway. Data volume 20 GiB and audit volume 10 GiB per pod (`deploy/platform/vault/values.yaml`).

## Secrets Manager

**What it holds.**

| Name | Holds | Read by |
|---|---|---|
| `pay-<env>-<region-short>-{router,locker,drainer,scheduler,control-center}` | service configuration shells (`infra/live/_envcommon/data/secrets.hcl`) | External Secrets (`aws-secrets-manager` store) |
| `<aurora cluster name>/proxy/hs_app`, `.../proxy/locker_app` | database logins for RDS Proxy | RDS Proxy |
| `pay/<env>/ratelimit/redis` | rate limit Redis password (`auth`) | rate limit service |
| `<prefix>/<env>/sentry/<service>-dsn` | Sentry DSN per service | router, drainer, scheduler |
| `<prefix>/shared-services/vault/init` | Vault recovery keys | break-glass only |
| `<prefix>/shared-services/*` | admin tool secrets (Okta clients, Grafana, Alertmanager webhooks) | central cluster |

**Writers and readers.** Terraform creates the containers only; no value is in state or code (except the generated admin-tool passwords listed in `infra/modules/central-secrets`). Operators enter values out of band.

**Consistency and retention.** Managed by AWS; the latest version wins.

**Backup and restore.** In prod, multi-Region replicas in us-east-1, read-only until promoted at a region switch.

**Encryption.** `shared` key per region (`infra/live/<env>/eu-central-1/secrets`).

**Size.** Not sized in the repo.

## Rate limit Redis

A small Redis endpoint used only by the global rate limit service at the edge (`deploy/platform/ratelimit`). It holds per-merchant counters for the current window; nothing else. Endpoint per environment in `deploy/platform/ratelimit/envs/<env>/<region>.yaml`, TLS on, password from `pay/<env>/ratelimit/redis`. Losing it loses only counters, and the edge fails open. See [payments-edge](payments-edge.md#ratelimit).

## Where in the repo

| Path | What |
|---|---|
| `infra/modules/memorydb`, `aurora-global`, `dynamodb-global`, `s3-backup`, `msk`, `clickhouse`, `opensearch`, `opensearch-indices`, `secrets-replica`, `central-secrets`, `vault-platform` | Store modules |
| `infra/live/_envcommon/data/`, `infra/live/_envcommon/analytics/` | Shared inputs and tags |
| `config/environments/<env>.yaml`, `infra/live/<env>/env.hcl` | Sizes |
| `deploy/platform/vault/` | Vault server, bootstrap, workload policies |
| `observability/alerts/data/`, `observability/alerts/backup-dr/` | Store and backup alerts |
| `docs/runbooks/data/`, `docs/runbooks/backup-dr/` | Their runbooks |
