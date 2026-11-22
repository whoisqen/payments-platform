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
}
