# data: non-paging alerts

Each section is the runbook of one ticket or Slack alert; the alert annotation links to its anchor. A ticket is handled in working hours; if the condition persists past the stated escalation, the owner raises it to the on-call.

## aurora-replica-lag-high

Alert `AuroraReplicaLagHigh`, severity warning, owner data-platform-oncall, dashboard https://grafana.payments.internal/d/data-stores.

### Symptom

CloudWatch reports an in-cluster replica lag above 1000 ms (the metric is in milliseconds).

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=AuroraReplicaLagHigh`) runs the read-only step of SSM document `pay-runbook-aurora-replica-lag-high`.
2. Check write volume and long transactions in `pg_stat_activity`.
3. Check the reader instance CPU and IOPS.

### Actions

1. Cancel the long transaction if it is not a migration.
2. Scale the reader up through Terraform if the load is sustained.

### Escalation

Ticket to data-platform; page only through the writer alert.

### SSM document

`pay-runbook-aurora-replica-lag-high`

## aurora-connections-high

Alert `AuroraConnectionsHigh`, severity warning, owner data-platform-oncall, dashboard https://grafana.payments.internal/d/data-stores.

### Symptom

The number of backends passed 80% of `max_connections`.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=AuroraConnectionsHigh`) runs the read-only step of SSM document `pay-runbook-aurora-connections-high`.
2. Check connections per application and per pool on the data-stores dashboard.
3. Check for a connection leak after a rollout.

### Actions

1. Lower the pool size of the service that leaks.
2. Add a connection proxy or raise the instance class through Terraform.

### Escalation

Ticket to data-platform; escalates to a page when above 95%.

### SSM document

`pay-runbook-aurora-connections-high`

## aurora-cpu-high

Alert `AuroraCpuHigh`, severity warning, owner data-platform-oncall, dashboard https://grafana.payments.internal/d/data-stores.

### Symptom

Instance CPU stays above 80%.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=AuroraCpuHigh`) runs the read-only step of SSM document `pay-runbook-aurora-cpu-high`.
2. Read the top queries by total time from `pg_stat_statements` on the data-stores dashboard.
3. Check a new migration or a batch job.

### Actions

1. Fix or index the top query through a migration.
2. Scale the instance class if the load is real.

### Escalation

Ticket to data-platform.

### SSM document

`pay-runbook-aurora-cpu-high`

## aurora-deadlocks

Alert `AuroraDeadlocks`, severity warning, owner data-platform-oncall, dashboard https://grafana.payments.internal/d/data-stores.

### Symptom

Deadlocks are counted continuously for 5 minutes.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=AuroraDeadlocks`) runs the read-only step of SSM document `pay-runbook-aurora-deadlocks`.
2. Read the deadlock details in the Aurora log (pgaudit is not needed).

### Actions

1. Fix the lock order in the code or the migration that causes it.

### Escalation

Ticket to the service owner through data-platform.

### SSM document

`pay-runbook-aurora-deadlocks`

## aurora-table-growth-fast

Alert `AuroraTableGrowthFast`, severity warning, owner data-platform-oncall, dashboard https://grafana.payments.internal/d/data-stores.

### Symptom

A table is more than 20% larger than 24 hours ago.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=AuroraTableGrowthFast`) runs the read-only step of SSM document `pay-runbook-aurora-table-growth-fast`.
2. Check the autovacuum state and bloat of the table.
3. Check whether a backfill or a retention job stopped.

### Actions

1. Fix the retention job or plan a partitioning change as an expand-contract migration.

### Escalation

Ticket to data-platform; feed the trend into the capacity review.

### SSM document

`pay-runbook-aurora-table-growth-fast`

## memory-db-failover-detected

Alert `MemoryDbFailoverDetected`, severity warning, owner data-platform-oncall, dashboard https://grafana.payments.internal/d/data-stores.

### Symptom

MemoryDB reported a failover in the last 10 minutes.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=MemoryDbFailoverDetected`) runs the read-only step of SSM document `pay-runbook-memory-db-failover-detected`.
2. Read the MemoryDB event for the cause (node failure, maintenance).

### Actions

1. Confirm the cache warm ratio recovers; see `cache-warm-ratio-low`.

### Escalation

Ticket to data-platform.

### SSM document

`pay-runbook-memory-db-failover-detected`

## cache-warm-ratio-low

Alert `CacheWarmRatioLow`, severity warning, owner payments-core-oncall, dashboard https://grafana.payments.internal/d/data-stores.

### Symptom

A cell took traffic after the 5-minute readiness wait with less than 75% of its priority keys loaded.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=CacheWarmRatioLow`) runs the read-only step of SSM document `pay-runbook-cache-warm-ratio-low`.
2. Check the warm-up job log: merchant configuration, routing and limits are loaded by priority.
3. Check Aurora read load during the warm-up.

### Actions

1. Restart the warm-up job with document step `rewarm-cache`.
2. No traffic action is needed: the cell already serves traffic.

### Escalation

Ticket only; this alert never pages (D8).

### SSM document

`pay-runbook-cache-warm-ratio-low`

## dynamo-db-throttling

Alert `DynamoDbThrottling`, severity warning, owner data-platform-oncall, dashboard https://grafana.payments.internal/d/data-stores.

### Symptom

Requests to a DynamoDB table are throttled.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=DynamoDbThrottling`) runs the read-only step of SSM document `pay-runbook-dynamo-db-throttling`.
2. Check consumed capacity against the provisioned or on-demand limit.
3. Check for a hot key in the contributor insights.

### Actions

1. Raise the capacity limit or fix the hot key.

### Escalation

Ticket to data-platform.

### SSM document

`pay-runbook-dynamo-db-throttling`

## click-house-replication-lag

Alert `ClickHouseReplicationLag`, severity warning, owner data-platform-oncall, dashboard https://grafana.payments.internal/d/data-stores.

### Symptom

A replica is more than 300 seconds behind.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=ClickHouseReplicationLag`) runs the read-only step of SSM document `pay-runbook-click-house-replication-lag`.
2. Check Keeper health and the replication queue length.

### Actions

1. Restart the lagging replica; if it fails, rebuild it from the hourly backup.

### Escalation

Ticket to data-platform; analytics are outside the payment path.

### SSM document

`pay-runbook-click-house-replication-lag`

## click-house-merge-backlog

Alert `ClickHouseMergeBacklog`, severity warning, owner data-platform-oncall, dashboard https://grafana.payments.internal/d/data-stores.

### Symptom

Merges do not keep up with inserts.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=ClickHouseMergeBacklog`) runs the read-only step of SSM document `pay-runbook-click-house-merge-backlog`.
2. Check the insert batch size of the Kafka consumer and the merge pool usage.

### Actions

1. Increase the batch size or the background pool through the configuration PR.

### Escalation

Ticket to data-platform.

### SSM document

`pay-runbook-click-house-merge-backlog`

## click-house-disk-low

Alert `ClickHouseDiskLow`, severity warning, owner data-platform-oncall, dashboard https://grafana.payments.internal/d/data-stores.

### Symptom

Free disk space is below 15%.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=ClickHouseDiskLow`) runs the read-only step of SSM document `pay-runbook-click-house-disk-low`.
2. Check the largest tables and the TTL moves to S3.

### Actions

1. Shorten the retention of the largest table through a PR or expand the volume through Terraform.

### Escalation

Ticket to data-platform; analytics are outside the payment path.

### SSM document

`pay-runbook-click-house-disk-low`

## open-search-disk-low

Alert `OpenSearchDiskLow`, severity warning, owner security-oncall, dashboard https://grafana.payments.internal/d/data-stores.

### Symptom

Free storage (in MB) of a data node dropped below 20480.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=OpenSearchDiskLow`) runs the read-only step of SSM document `pay-runbook-open-search-disk-low`.
2. Check the index lifecycle: hot retention is 3 months.

### Actions

1. Delete expired indices through the lifecycle policy or add storage through Terraform.

### Escalation

Ticket to security and data-platform.

### SSM document

`pay-runbook-open-search-disk-low`

## kafka-consumer-lag-high

Alert `KafkaConsumerLagHigh`, severity warning, owner data-platform-oncall, dashboard https://grafana.payments.internal/d/data-stores.

### Symptom

A consumer group is more than 100000 messages behind.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=KafkaConsumerLagHigh`) runs the read-only step of SSM document `pay-runbook-kafka-consumer-lag-high`.
2. Check the consumer pods and the ClickHouse insert errors.

### Actions

1. Scale the consumers or fix the failing sink.

### Escalation

Ticket to data-platform.

### SSM document

`pay-runbook-kafka-consumer-lag-high`

## kafka-under-replicated-partitions

Alert `KafkaUnderReplicatedPartitions`, severity warning, owner data-platform-oncall, dashboard https://grafana.payments.internal/d/data-stores.

### Symptom

Some partitions have fewer in-sync replicas than the replication factor.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=KafkaUnderReplicatedPartitions`) runs the read-only step of SSM document `pay-runbook-kafka-under-replicated-partitions`.
2. Check broker health and disk in the MSK console metrics.

### Actions

1. Replace the unhealthy broker through MSK; wait for the ISR to recover.

### Escalation

Ticket to data-platform.

### SSM document

`pay-runbook-kafka-under-replicated-partitions`

## kafka-broker-disk-high

Alert `KafkaBrokerDiskHigh`, severity warning, owner data-platform-oncall, dashboard https://grafana.payments.internal/d/data-stores.

### Symptom

Broker data volume use is above 80%.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=KafkaBrokerDiskHigh`) runs the read-only step of SSM document `pay-runbook-kafka-broker-disk-high`.
2. Check topic retention (7 days) against the ingest rate.

### Actions

1. Enable MSK storage auto-scaling or shorten retention through the Kafka-as-code PR.

### Escalation

Ticket to data-platform.

### SSM document

`pay-runbook-kafka-broker-disk-high`
