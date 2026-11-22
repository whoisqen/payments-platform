from common import a, gap

L = "data"
DS = "data-stores"

a(layer=L, group="aurora", name="AuroraWriterUnavailable", sev="critical", team="data-platform", svc="aurora", comp="aurora", dash=DS,
  expr='pg_up{role="writer"} == 0', f="2m",
  sum="The Aurora writer of a cell does not answer",
  series=[('pg_up{role="writer",cell="cell-1"}', "0x{n}", "1x{n}")],
  failure="Aurora writer unavailable", impact="drainer cannot write; the stream grows and the drain lag rises; reads of payment history fail",
  sym="postgres_exporter cannot reach the writer endpoint of a cell for 2 minutes.",
  diag=["Check the RDS event stream for a failover or maintenance event of the cluster.", "Check the cluster writer instance and its AZ in the data-stores dashboard.", "Check the drain lag and Redis stream length: they show how much write-behind is pending."],
  act=["If a failover is in progress, wait for it and watch the stream drain; no manual action while the writer is promoted.", "If no failover started and the instance is unhealthy, start a failover with document step `failover-cluster`.", "Keep the router running: payments continue in MemoryDB until the stream limit is reached."],
  esc="Escalate to the commander when the stream length passes 50000 (alert RedisStreamBacklog) or the writer is down for more than 10 minutes.")

a(layer=L, group="aurora", name="AuroraReplicationSlotLagHigh", sev="critical", team="data-platform", svc="aurora", comp="aurora", dash=DS,
  expr="max by (cell, slot_name) (pg_replication_slots_wal_lag_bytes) > 10 * 1024 ^ 3", f="10m",
  sum="A replication slot retains more than 10 GiB of WAL",
  series=[('pg_replication_slots_wal_lag_bytes{cell="cell-1",slot_name="cdc_clickhouse"}', "20000000000x{n}", "1000x{n}")],
  failure="replication slot holds WAL", impact="storage growth and a risk of write stop and of an unusable restore point",
  sym="A logical replication slot, usually the analytics change stream, is not consumed and retains WAL.",
  diag=["Identify the slot and its consumer in `pg_replication_slots`.", "Check the consumer (Kafka connector) health and its lag."],
  act=["Restart the stuck consumer.", "If the consumer cannot catch up within 30 minutes, drop the slot with document step `drop-slot` and re-snapshot the analytics stream from the archive."],
  esc="Escalate to the commander if storage free space drops below 20% of the cluster volume.")

a(layer=L, group="aurora", name="AuroraReplicaLagHigh", sev="warning", team="data-platform", svc="aurora", comp="aurora", dash=DS,
  expr="max by (cell) (aws_rds_aurora_replica_lag_maximum) > 1000", f="5m",
  sum="Aurora replica lag is above 1 second",
  series=[('aws_rds_aurora_replica_lag_maximum{cell="cell-1"}', "2500x{n}", "20x{n}")],
  failure="reader replica lag", impact="stale reads; reader promotion would lose recent rows",
  sym="CloudWatch reports an in-cluster replica lag above 1000 ms (the metric is in milliseconds).",
  diag=["Check write volume and long transactions in `pg_stat_activity`.", "Check the reader instance CPU and IOPS."],
  act=["Cancel the long transaction if it is not a migration.", "Scale the reader up through Terraform if the load is sustained."],
  esc="Ticket to data-platform; page only through the writer alert.")

a(layer=L, group="aurora", name="AuroraConnectionsHigh", sev="warning", team="data-platform", svc="aurora", comp="aurora", dash=DS,
  expr="sum by (cell, instance) (pg_stat_database_numbackends) / max by (cell, instance) (pg_settings_max_connections) > 0.8", f="5m",
  sum="Aurora connections exceed 80% of the limit",
  series=[('pg_stat_database_numbackends{cell="cell-1",instance="writer"}', "900x{n}", "100x{n}"), ('pg_settings_max_connections{cell="cell-1",instance="writer"}', "1000x{n}", "1000x{n}")],
  labels={"cell": "cell-1", "instance": "writer"},
  failure="connection exhaustion", impact="new connections are refused and requests fail",
  sym="The number of backends passed 80% of `max_connections`.",
  diag=["Check connections per application and per pool on the data-stores dashboard.", "Check for a connection leak after a rollout."],
  act=["Lower the pool size of the service that leaks.", "Add a connection proxy or raise the instance class through Terraform."],
  esc="Ticket to data-platform; escalates to a page when above 95%.")

a(layer=L, group="aurora", name="AuroraCpuHigh", sev="warning", team="data-platform", svc="aurora", comp="aurora", dash=DS,
  expr="max by (cell, instance) (aws_rds_cpuutilization_average) > 80", f="15m",
  sum="Aurora CPU above 80% for 15 minutes",
  series=[('aws_rds_cpuutilization_average{cell="cell-1",instance="writer"}', "92x{n}", "30x{n}")],
  failure="Aurora CPU saturation", impact="latency growth in drainer batches and reads",
  sym="Instance CPU stays above 80%.",
  diag=["Read the top queries by total time from `pg_stat_statements` on the data-stores dashboard.", "Check a new migration or a batch job."],
  act=["Fix or index the top query through a migration.", "Scale the instance class if the load is real."],
  esc="Ticket to data-platform.")

a(layer=L, group="aurora", name="AuroraDeadlocks", sev="warning", team="data-platform", svc="aurora", comp="aurora", dash=DS,
  expr="sum by (cell) (rate(pg_stat_database_deadlocks[5m])) > 0", f="5m",
  sum="Aurora reports deadlocks",
  series=[('pg_stat_database_deadlocks{cell="cell-1"}', "0+1x{n}", "0+0x{n}")],
  failure="deadlocks", impact="failed transactions; the drainer retries the batch",
  sym="Deadlocks are counted continuously for 5 minutes.",
  diag=["Read the deadlock details in the Aurora log (pgaudit is not needed)."],
  act=["Fix the lock order in the code or the migration that causes it."],
  esc="Ticket to the service owner through data-platform.")

a(layer=L, group="aurora", name="AuroraTableGrowthFast", sev="warning", team="data-platform", svc="aurora", comp="aurora", dash=DS,
  expr="max by (cell, relname) (pg_table_size_bytes) / max by (cell, relname) (pg_table_size_bytes offset 1d) > 1.2", f="1h",
  sum="A table grew more than 20% in a day",
  series=[('pg_table_size_bytes{cell="cell-1",relname="payment_attempt"}', "100x1440 300x{n}", "100x{n}")],
  labels={"cell": "cell-1", "relname": "payment_attempt"}, T=1510, spike=False,
  failure="fast table growth", impact="capacity and restore time (D4 target 30 minutes) grow with data size",
  sym="A table is more than 20% larger than 24 hours ago.",
  diag=["Check the autovacuum state and bloat of the table.", "Check whether a backfill or a retention job stopped."],
  act=["Fix the retention job or plan a partitioning change as an expand-contract migration."],
  esc="Ticket to data-platform; feed the trend into the capacity review.")

a(layer=L, group="memorydb", name="MemoryDbMemoryCritical", sev="critical", team="data-platform", svc="memorydb", comp="memorydb", dash=DS,
  expr="max by (cell, instance) (redis_memory_used_bytes / redis_memory_max_bytes) > 0.85", f="5m",
  sum="MemoryDB memory above 85%, evictions are near",
  series=[('redis_memory_used_bytes{cell="cell-1",instance="shard-1"}', "9x{n}", "5x{n}"), ('redis_memory_max_bytes{cell="cell-1",instance="shard-1"}', "10x{n}", "10x{n}")],
  failure="MemoryDB memory exhaustion", impact="payment state keys can be evicted or writes rejected; MemoryDB is the hot path",
  sym="MemoryDB memory use is above 85% of the node maximum.",
  diag=["Check the drainer: a stalled drainer keeps stream entries in memory.", "Check the largest key groups and the stream length on the data-stores dashboard."],
  act=["If the drainer is behind, follow `drain-lag-high` first.", "Scale the shard out with document step `scale-memorydb`; online resharding is supported.", "Never flush keys to free memory: payment state lives there."],
  esc="Escalate to the commander when above 92%.")

a(layer=L, group="memorydb", name="MemoryDbEvictions", sev="critical", team="data-platform", svc="memorydb", comp="memorydb", dash=DS,
  expr="sum by (cell) (rate(redis_evicted_keys_total[5m])) > 0", f="5m",
  sum="MemoryDB evicts keys",
  series=[('redis_evicted_keys_total{cell="cell-1"}', "0+5x{n}", "0+0x{n}")],
  failure="MemoryDB evicts keys", impact="payment state or idempotency keys are lost before they are drained to Aurora",
  sym="MemoryDB evicts keys; the policy should be `noeviction`, so any eviction is a configuration or capacity fault.",
  diag=["Check the parameter group `maxmemory-policy` of the cluster.", "Check which key prefix is evicted from the slow log and memory stats."],
  act=["Restore `noeviction` through Terraform if the policy drifted.", "Scale out as in `memory-db-memory-critical`.", "Run a reconciliation of unknown-state payments with the PSP after the incident."],
  esc="Escalate to the commander at once: possible loss of idempotency keys.")

a(layer=L, group="memorydb", name="MemoryDbFailoverDetected", sev="warning", team="data-platform", svc="memorydb", comp="memorydb", dash=DS,
  expr="sum by (cell, shard) (increase(memorydb_failover_events_total[10m])) > 0", f="0m",
  sum="A MemoryDB shard failed over",
  series=[('memorydb_failover_events_total{cell="cell-1",shard="1"}', "0+1x{n}", "0+0x{n}")],
  failure="MemoryDB shard failover", impact="a short write pause; the cache warms again after a node replacement",
  sym="MemoryDB reported a failover in the last 10 minutes.",
  diag=["Read the MemoryDB event for the cause (node failure, maintenance)."],
  act=["Confirm the cache warm ratio recovers; see `cache-warm-ratio-low`."],
  esc="Ticket to data-platform.")

a(layer=L, group="memorydb", name="CacheWarmRatioLow", sev="warning", team="payments-core", svc="memorydb", comp="cache", dash=DS,
  expr="min by (cell) (cache_warm_ratio) < 0.75", f="5m",
  sum="Cache warm ratio stays below 75% five minutes after readiness (non-paging)",
  series=[('cache_warm_ratio{cell="cell-1"}', "0.4x{n}", "0.95x{n}")],
  failure="cache not warm after replacement", impact="higher latency and Aurora load while the cell takes traffic anyway (D8)",
  sym="A cell took traffic after the 5-minute readiness wait with less than 75% of its priority keys loaded.",
  diag=["Check the warm-up job log: merchant configuration, routing and limits are loaded by priority.", "Check Aurora read load during the warm-up."],
  act=["Restart the warm-up job with document step `rewarm-cache`.", "No traffic action is needed: the cell already serves traffic."],
  esc="Ticket only; this alert never pages (D8).")

a(layer=L, group="stores", name="DynamoDbThrottling", sev="warning", team="data-platform", svc="dynamodb", comp="dynamodb", dash=DS,
  expr="sum by (table_name) (rate(aws_dynamodb_throttled_requests_sum[5m])) > 0", f="5m",
  sum="DynamoDB throttles requests",
  series=[('aws_dynamodb_throttled_requests_sum{table_name="merchant-cell-map"}', "0+3x{n}", "0+0x{n}")],
  failure="DynamoDB throttling", impact="merchant-to-cell lookups slow down; router caches cover short throttling",
  sym="Requests to a DynamoDB table are throttled.",
  diag=["Check consumed capacity against the provisioned or on-demand limit.", "Check for a hot key in the contributor insights."],
  act=["Raise the capacity limit or fix the hot key."],
  esc="Ticket to data-platform.")

a(layer=L, group="stores", name="ClickHouseReplicationLag", sev="warning", team="data-platform", svc="clickhouse", comp="clickhouse", dash=DS,
  expr="max by (cluster) (ClickHouseAsyncMetrics_ReplicasMaxAbsoluteDelay) > 300", f="10m",
  sum="ClickHouse replication delay above 5 minutes",
  series=[('ClickHouseAsyncMetrics_ReplicasMaxAbsoluteDelay{cluster="analytics"}', "900x{n}", "2x{n}")],
  failure="ClickHouse replica delay", impact="stale analytics; a failover loses recent inserts",
  sym="A replica is more than 300 seconds behind.",
  diag=["Check Keeper health and the replication queue length."],
  act=["Restart the lagging replica; if it fails, rebuild it from the hourly backup."],
  esc="Ticket to data-platform; analytics are outside the payment path.")

a(layer=L, group="stores", name="ClickHouseMergeBacklog", sev="warning", team="data-platform", svc="clickhouse", comp="clickhouse", dash=DS,
  expr="max by (cluster) (ClickHouseAsyncMetrics_MaxPartCountForPartition) > 300", f="15m",
  sum="ClickHouse has too many parts per partition",
  series=[('ClickHouseAsyncMetrics_MaxPartCountForPartition{cluster="analytics"}', "450x{n}", "20x{n}")],
  failure="merge backlog", impact="inserts are throttled and then rejected",
  sym="Merges do not keep up with inserts.",
  diag=["Check the insert batch size of the Kafka consumer and the merge pool usage."],
  act=["Increase the batch size or the background pool through the configuration PR."],
  esc="Ticket to data-platform.")

a(layer=L, group="stores", name="ClickHouseDiskLow", sev="warning", team="data-platform", svc="clickhouse", comp="clickhouse", dash=DS,
  expr="min by (cluster, instance) (ClickHouseAsyncMetrics_DiskAvailable_default / ClickHouseAsyncMetrics_DiskTotal_default) < 0.15", f="10m",
  sum="ClickHouse disk has less than 15% free",
  series=[('ClickHouseAsyncMetrics_DiskAvailable_default{cluster="analytics",instance="ch-1"}', "10x{n}", "60x{n}"), ('ClickHouseAsyncMetrics_DiskTotal_default{cluster="analytics",instance="ch-1"}', "100x{n}", "100x{n}")],
  failure="ClickHouse disk full", impact="inserts stop; analytics are restored from the hourly backup if corrupted",
  sym="Free disk space is below 15%.",
  diag=["Check the largest tables and the TTL moves to S3."],
  act=["Shorten the retention of the largest table through a PR or expand the volume through Terraform."],
  esc="Ticket to data-platform; analytics are outside the payment path.")

a(layer=L, group="stores", name="OpenSearchClusterRed", sev="critical", team="security", svc="opensearch", comp="opensearch", dash=DS,
  expr="max by (domain_name) (aws_es_cluster_statusred_maximum) >= 1", f="5m",
  sum="OpenSearch domain status is red",
  series=[('aws_es_cluster_statusred_maximum{domain_name="audit"}', "1x{n}", "0x{n}")],
  failure="OpenSearch red", impact="audit logs are not searchable or not ingested; PCI DSS 10.5.1 needs 3 months online",
  sym="At least one primary shard of the audit domain is unassigned.",
  diag=["Check the shard allocation explanation and the free storage of the domain.", "Check that the Firehose delivery to S3 Object Lock still works: the archive is the source of truth."],
  act=["Free storage or add a data node with document step `scale-opensearch`.", "Retry shard allocation after the cause is fixed."],
  esc="Security on-call is informed because the audit trail is degraded; the S3 archive keeps the logs meanwhile.")

a(layer=L, group="stores", name="OpenSearchDiskLow", sev="warning", team="security", svc="opensearch", comp="opensearch", dash=DS,
  expr="min by (domain_name) (aws_es_free_storage_space_minimum) < 20480", f="10m",
  sum="OpenSearch has less than 20 GiB free per node",
  series=[('aws_es_free_storage_space_minimum{domain_name="audit"}', "10000x{n}", "90000x{n}")],
  failure="OpenSearch storage low", impact="shards may become read-only",
  sym="Free storage (in MB) of a data node dropped below 20480.",
  diag=["Check the index lifecycle: hot retention is 3 months."],
  act=["Delete expired indices through the lifecycle policy or add storage through Terraform."],
  esc="Ticket to security and data-platform.")

a(layer=L, group="kafka", name="KafkaConsumerLagHigh", sev="warning", team="data-platform", svc="kafka", comp="msk", dash=DS,
  expr="sum by (consumergroup, topic) (kafka_consumergroup_lag) > 100000", f="10m",
  sum="Kafka consumer lag above 100000 messages",
  series=[('kafka_consumergroup_lag{consumergroup="clickhouse-sink",topic="payment-events"}', "250000x{n}", "100x{n}")],
  labels={"consumergroup": "clickhouse-sink", "topic": "payment-events"},
  failure="consumer lag", impact="analytics are late; the payment path is not affected (it accepts payments without MSK)",
  sym="A consumer group is more than 100000 messages behind.",
  diag=["Check the consumer pods and the ClickHouse insert errors."],
  act=["Scale the consumers or fix the failing sink."],
  esc="Ticket to data-platform.")

a(layer=L, group="kafka", name="KafkaUnderReplicatedPartitions", sev="warning", team="data-platform", svc="kafka", comp="msk", dash=DS,
  expr="max by (cluster) (kafka_server_replicamanager_underreplicatedpartitions) > 0", f="5m",
  sum="Kafka has under-replicated partitions",
  series=[('kafka_server_replicamanager_underreplicatedpartitions{cluster="msk-main"}', "3x{n}", "0x{n}")],
  failure="under-replicated partitions", impact="reduced durability of events with RF 3; the S3 sink keeps the archive",
  sym="Some partitions have fewer in-sync replicas than the replication factor.",
  diag=["Check broker health and disk in the MSK console metrics."],
  act=["Replace the unhealthy broker through MSK; wait for the ISR to recover."],
  esc="Ticket to data-platform.")

a(layer=L, group="kafka", name="KafkaBrokerDiskHigh", sev="warning", team="data-platform", svc="kafka", comp="msk", dash=DS,
  expr="max by (broker_id) (aws_kafka_kafka_data_logs_disk_used_average) > 80", f="10m",
  sum="A Kafka broker disk is more than 80% full",
  series=[('aws_kafka_kafka_data_logs_disk_used_average{broker_id="1"}', "90x{n}", "40x{n}")],
  failure="broker disk full", impact="the broker stops accepting writes",
  sym="Broker data volume use is above 80%.",
  diag=["Check topic retention (7 days) against the ingest rate."],
  act=["Enable MSK storage auto-scaling or shorten retention through the Kafka-as-code PR."],
  esc="Ticket to data-platform.")

gap(L, "memorydb-replica-lag", "memorydb", "MemoryDB replica replication lag", "failover loses the most recent writes of the shard", "warning", "metric `redis_replication_lag` is not scraped yet")
gap(L, "opensearch-jvm-pressure", "opensearch", "OpenSearch JVM memory pressure", "slow audit search and node restarts", "warning", "YACE job for the domain JVM metric is not configured yet")
