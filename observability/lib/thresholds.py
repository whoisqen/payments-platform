"""Single source of the numbers that alerts and dashboard thresholds share (section 15)."""

DRAIN_LAG_S = 5
REDIS_STREAM_LEN = 50000
SCHEDULER_QUEUE_S = 600
MEMORYDB_MEM_WARN = 0.7
MEMORYDB_MEM_CRIT = 0.85
AURORA_REPLICA_LAG_MS = 1000
AURORA_GLOBAL_LAG_MS = 5000
AURORA_RPO_BUDGET_MS = 10000
PSP_ERROR_RATIO = 0.05
PSP_P99_S = 3
ROUTER_5XX_RATIO = 0.01
CACHE_WARM_RATIO = 0.75
RESTORABLE_LAG_S = 300
RESTORE_TARGET_FRACTION = 0.8
AURORA_CONNECTIONS_RATIO = 0.8
LOCKER_5XX_RATIO = 0.01
RETRY_RATIO = 0.1
WEBHOOK_AGE_S = 300
DR_TEST_OVERDUE_D = 100
S3_REPLICATION_S = 900
SNAPSHOT_COPY_STALE_S = 2 * 3600
DYNAMODB_GLOBAL_LAG_MS = 5000
AURORA_CPU_PCT = 80
KAFKA_LAG = 100000
CLICKHOUSE_DELAY_S = 300
CLICKHOUSE_DISK_FREE_RATIO = 0.15
SUBNET_FREE_IP_RATIO = 0.2
OS_JVM_WARN_PCT = 80
OS_JVM_CRIT_PCT = 92
OS_CPU_PCT = 80
OS_FREE_PCT = 20
OS_SHARDS_PER_NODE = 900
LOGSTASH_QUEUE_WARN = 0.5
LOGSTASH_QUEUE_CRIT = 0.8
LOGSTASH_HEAP_PCT = 85
CLOCK_DRIFT_S = 0.1
CERT_EXPIRY_CRIT_D = 14
WAF_BLOCKED_RPS = 100
FIREWALL_DROPS_PPS = 1000
CLOUDFRONT_5XX_PCT = 5

# Alert name -> constant; tests assert the number appears in the alert expression.
ALERT_LINKS = {
    "DrainLagHigh": "DRAIN_LAG_S",
    "RedisStreamBacklog": "REDIS_STREAM_LEN",
    "SchedulerQueueDelayHigh": "SCHEDULER_QUEUE_S",
    "MemoryDbMemoryCritical": "MEMORYDB_MEM_CRIT",
    "AuroraReplicaLagHigh": "AURORA_REPLICA_LAG_MS",
    "AuroraGlobalLagHigh": "AURORA_GLOBAL_LAG_MS",
    "AuroraGlobalLagRpoBudgetExceeded": "AURORA_RPO_BUDGET_MS",
    "PSPDegraded": "PSP_ERROR_RATIO",
    "PspLatencyP99High": "PSP_P99_S",
    "Router5xxRateHigh": "ROUTER_5XX_RATIO",
    "CacheWarmRatioLow": "CACHE_WARM_RATIO",
    "LatestRestorableTimeLagHigh": "RESTORABLE_LAG_S",
    "RestoreDurationNearTarget": "RESTORE_TARGET_FRACTION",
    "AuroraConnectionsHigh": "AURORA_CONNECTIONS_RATIO",
    "LockerErrorRateHigh": "LOCKER_5XX_RATIO",
    "RetryStorm": "RETRY_RATIO",
    "WebhookBacklogOld": "WEBHOOK_AGE_S",
    "DrSwitchTestOverdue": "DR_TEST_OVERDUE_D",
    "S3ReplicationLagHigh": "S3_REPLICATION_S",
    "DynamoDbGlobalTableLagHigh": "DYNAMODB_GLOBAL_LAG_MS",
    "AuroraCpuHigh": "AURORA_CPU_PCT",
    "KafkaConsumerLagHigh": "KAFKA_LAG",
    "ClickHouseReplicationLag": "CLICKHOUSE_DELAY_S",
    "ClickHouseDiskLow": "CLICKHOUSE_DISK_FREE_RATIO",
    "SubnetFreeIpsLow": "SUBNET_FREE_IP_RATIO",
    "NodeClockDrift": "CLOCK_DRIFT_S",
    "CertificateExpiryCritical": "CERT_EXPIRY_CRIT_D",
    "WafBlockedRequestsHigh": "WAF_BLOCKED_RPS",
    "NetworkFirewallDropsHigh": "FIREWALL_DROPS_PPS",
    "CloudFront5xxHigh": "CLOUDFRONT_5XX_PCT",
    "LogsOpenSearchJvmPressureHigh": "OS_JVM_WARN_PCT",
    "LogsOpenSearchJvmPressureCritical": "OS_JVM_CRIT_PCT",
    "LogsOpenSearchCpuHigh": "OS_CPU_PCT",
    "LogsOpenSearchStorageLow": "OS_FREE_PCT",
    "LogsOpenSearchShardsPerNodeHigh": "OS_SHARDS_PER_NODE",
    "LogstashQueueBacklogHigh": "LOGSTASH_QUEUE_WARN",
    "LogstashQueueNearlyFull": "LOGSTASH_QUEUE_CRIT",
    "LogstashJvmHeapHigh": "LOGSTASH_HEAP_PCT",
}
