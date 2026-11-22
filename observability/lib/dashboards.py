"""Dashboard definitions by level (section 15 hierarchy); thresholds come from thresholds.py."""
import thresholds as T
from panels import F, FC, Dashboard, steps

PCT = dict(unit="percent", lo=0, hi=100)
NAV_ALL = [("platform-overview", "L0 Platform overview"), ("slo-overview", "L0 SLO"), ("payments", "L1 Payments and PSP"), ("cells", "L2 Cells"), ("data-stores", "L3 Data stores")]


def nav(*keep):
    return [x for x in NAV_ALL if x[0] in keep]


def req_rate(extra=""):
    return f'sum by (cell) (rate(http_server_requests_total{{{FC},service=~"$service"{extra}}}[5m]))'


def err_ratio(extra=""):
    return (f'100 * sum by (cell) (rate(http_server_requests_total{{{FC},service=~"$service",code=~"5.."{extra}}}[5m]))'
            f' / sum by (cell) (rate(http_server_requests_total{{{FC},service=~"$service"{extra}}}[5m]))')


def quantile(q, metric, by="cell", extra=""):
    return f'histogram_quantile({q}, sum by ({by}, le) (rate({metric}_bucket{{{FC},service=~"$service"{extra}}}[5m])))'


def red(d, service_title):
    d.row("Overview")
    d.stat(f"{service_title}: requests per second", f'sum(rate(http_server_requests_total{{{FC},service=~"$service"}}[5m]))', "reqps", thr=steps(info=True))
    d.stat(f"{service_title}: 5xx share, %", err_ratio().replace("by (cell) ", ""), "percent", lo=0, hi=100, thr=steps(T.ROUTER_5XX_RATIO * 100, 5))
    d.stat(f"{service_title}: p99 latency, s", quantile(0.99, "http_server_request_duration_seconds", by="service"), "s", thr=steps(0.3, 1), decimals=3)
    d.stat(f"{service_title}: ready replicas", f'sum(kube_deployment_status_replicas_ready{{{F},deployment=~"$service.*"}})', "short", lo=0, thr=steps(info=True))
    d.row("Traffic")
    d.ts(f"{service_title}: requests per second by cell, reqps", [(req_rate(), "{{cell}}")], "reqps")
    d.ts(f"{service_title}: requests per second by status class, reqps", [(f'sum by (code) (rate(http_server_requests_total{{{FC},service=~"$service"}}[5m]))', "{{code}}")], "reqps")
    d.row("Errors")
    d.ts(f"{service_title}: 5xx share by cell, %", [(err_ratio(), "{{cell}}")], "percent", lo=0, hi=100, thr=steps(T.ROUTER_5XX_RATIO * 100, 5), w=24)
    d.row("Latency")
    d.ts(f"{service_title}: p50, p95, p99 latency, s", [(quantile(0.5, "http_server_request_duration_seconds", by="service"), "p50"), (quantile(0.95, "http_server_request_duration_seconds", by="service"), "p95"),
                                                    (quantile(0.99, "http_server_request_duration_seconds", by="service"), "p99")], "s", exemplar=True, desc="Exemplars link a latency peak to a trace in Tempo.")
    d.heatmap(f"{service_title}: latency distribution, s", f'sum by (le) (increase(http_server_request_duration_seconds_bucket{{{FC},service=~"$service"}}[5m]))')
    d.row("Resources")
    d.ts(f"{service_title}: CPU use, % of limit", [(f'100 * sum by (pod) (rate(container_cpu_usage_seconds_total{{{F},pod=~"$service.*"}}[5m])) / sum by (pod) (kube_pod_container_resource_limits{{{F},pod=~"$service.*",resource="cpu"}})', "{{pod}}")], "percent", lo=0, hi=100, thr=steps(70, 90))
    d.ts(f"{service_title}: memory working set, bytes", [(f'sum by (pod) (container_memory_working_set_bytes{{{F},pod=~"$service.*"}})', "{{pod}}")], "bytes")


def build_all():
    out = []

    d = Dashboard("platform-overview", "Platform overview", "l0", ["overview"], links=nav("slo-overview", "payments", "cells"), description="Are payments going through right now?")
    d.row("Overview")
    d.stat("platform: authorization rate, %", f'100 * sum(rate(payment_attempts_total{{{FC},outcome="authorized"}}[15m])) / sum(rate(payment_attempts_total{{{FC}}}[15m]))', "percent", lo=0, hi=100, thr=steps(90, 80, invert=True), decimals=2,
           desc="Share of successful authorizations among all payment attempts of the last 15 minutes.")
    d.stat("platform: payments per second", f'sum(rate(payment_attempts_total{{{FC}}}[5m]))', "reqps", decimals=0)
    d.stat("authorization SLO: error budget left, %", f'100 * slo:period_error_budget_remaining:ratio{{env=~"$env",sloth_id="payments-authorization-availability"}}', "percent", lo=0, hi=100, thr=steps(50, 20, invert=True))
    d.stat("platform: firing critical alerts", 'count(ALERTS{alertstate="firing",severity=~"critical|security",env=~"$env"}) or vector(0)', "short", lo=0, thr=steps(1, 1))
    d.stat("drainer: drain lag, s", f'max(drain_lag_seconds{{{FC}}})', "s", lo=0, thr=steps(T.DRAIN_LAG_S, T.DRAIN_LAG_S * 2), decimals=2)
    d.stat("scheduler: unknown-state payments older than 15 min", f'sum(payments_unknown_state_stale{{{FC}}})', "short", lo=0, thr=steps(1, 100))
    d.row("Traffic")
    d.ts("platform: payments per second by cell, reqps", [(f'sum by (cell) (rate(payment_attempts_total{{{FC}}}[5m]))', "{{cell}}")], "reqps")
    d.ts("platform: authorization rate by cell, %", [(f'100 * sum by (cell) (rate(payment_attempts_total{{{FC},outcome="authorized"}}[15m])) / sum by (cell) (rate(payment_attempts_total{{{FC}}}[15m]))', "{{cell}}")], "percent", lo=0, hi=100, thr=steps(90, 80, invert=True))
    d.row("Errors")
    d.ts("router: 5xx share by cell, %", [(err_ratio().replace("$service", "router"), "{{cell}}")], "percent", lo=0, hi=100, thr=steps(T.ROUTER_5XX_RATIO * 100, 5), w=24)
    d.row("Latency")
    d.ts("router: p99 platform overhead, s", [(f'histogram_quantile(0.99, sum by (cell, le) (rate(platform_overhead_seconds_bucket{{{FC}}}[5m])))', "{{cell}}")], "s", thr=steps(0.15, 0.3), exemplar=True, decimals=3, w=24,
         desc="Platform time on top of the PSP time; the SLO is 150 ms at p99.")
    out.append(("l0-overview", d))

    d = Dashboard("slo-overview", "SLO overview", "l0", ["slo"], links=nav("platform-overview", "payments"), description="How much budget is left and how fast it burns.")
    slos = [("payments-authorization-availability", "authorization availability"), ("payments-platform-overhead-latency", "platform overhead latency"), ("payments-status-read", "status read"), ("payments-webhooks-delivery", "webhook delivery")]
    d.row("Error budget left")
    for sid, name in slos:
        d.gauge(f"slo: {name}, budget left %", f'100 * slo:period_error_budget_remaining:ratio{{env=~"$env",sloth_id="{sid}"}}', "percent", 0, 100, steps(50, 20, invert=True))
    d.row("Burn rate")
    burn = '/ on(env, region, sloth_id, sloth_slo, sloth_service) slo:error_budget:ratio'
    d.ts("slo: burn rate over 1 h, x budget", [(f'slo:sli_error:ratio_rate1h{{env=~"$env"}} {burn}', "{{sloth_id}}")], "none", thr=steps(6, 14.4), desc="14.4 pages (2% of the budget per hour); 6 pages over 6 hours.")
    d.ts("slo: burn rate over 6 h, x budget", [(f'slo:sli_error:ratio_rate6h{{env=~"$env"}} {burn}', "{{sloth_id}}")], "none", thr=steps(1, 6))
    d.ts("slo: burn rate over 5 min, x budget", [(f'slo:sli_error:ratio_rate5m{{env=~"$env"}} {burn}', "{{sloth_id}}")], "none", thr=steps(14.4, 50), desc="50 pages for the 99.99% authorization SLO.")
    d.ts("slo: burn rate over 3 days, x budget", [(f'slo:sli_error:ratio_rate3d{{env=~"$env"}} {burn}', "{{sloth_id}}")], "none", thr=steps(1, 3))
    out.append(("l0-overview", d))

    d = Dashboard("payments", "Payments and PSP health", "l1", ["psp", "payments"], links=nav("platform-overview", "slo-overview", "cells"), description="Which PSP degrades?")
    d.row("Overview")
    d.stat("platform: authorization rate, %", f'100 * sum(rate(payment_attempts_total{{{FC},outcome="authorized",psp=~"$psp"}}[15m])) / sum(rate(payment_attempts_total{{{FC},psp=~"$psp"}}[15m]))', "percent", lo=0, hi=100, thr=steps(90, 80, invert=True), decimals=2)
    d.stat("scheduler: unknown-state payments older than 15 min", f'sum(payments_unknown_state_stale{{{FC}}})', "short", lo=0, thr=steps(1, 100))
    d.stat("router: open PSP circuit breakers", f'count(circuit_breaker_state{{{F},dependency="psp-authorize",psp=~"$psp"}} == 2) or vector(0)', "short", lo=0, thr=steps(1, 2))
    d.stat("reconciliation: amount mismatches, 24 h", f'sum(increase(reconciliation_amount_mismatch_total{{{F},psp=~"$psp"}}[1d]))', "short", lo=0, thr=steps(1, 5))
    d.row("PSP")
    d.bars("router: authorization rate by PSP, %", f'100 * sum by (psp) (rate(payment_attempts_total{{{FC},outcome="authorized",psp=~"$psp"}}[15m])) / sum by (psp) (rate(payment_attempts_total{{{FC},psp=~"$psp"}}[15m]))', "{{psp}}", "percent", lo=0, hi=100, thr=steps(90, 80, invert=True))
    d.ts("router: PSP technical error share, %", [(f'100 * sum by (psp) (rate(psp_requests_total{{{FC},outcome="technical_error",psp=~"$psp"}}[5m])) / sum by (psp) (rate(psp_requests_total{{{FC},psp=~"$psp"}}[5m]))', "{{psp}}")], "percent", lo=0, hi=100, thr=steps(T.PSP_ERROR_RATIO * 100, 10))
    d.heatmap("router: PSP call latency distribution, s", f'sum by (le) (increase(psp_request_duration_seconds_bucket{{{FC},psp=~"$psp"}}[5m]))')
    d.ts("router: PSP p99 latency, s", [(f'histogram_quantile(0.99, sum by (psp, le) (rate(psp_request_duration_seconds_bucket{{{FC},psp=~"$psp"}}[5m])))', "{{psp}}")], "s", thr=steps(T.PSP_P99_S, 10), exemplar=True)
    d.row("Attempts")
    d.ts("router: payment attempts by outcome, reqps", [(f'sum by (outcome) (rate(payment_attempts_total{{{FC},psp=~"$psp"}}[5m]))', "{{outcome}}")], "reqps")
    d.ts("router: authorization rate against the same time last week, %", [(f'100 * sum(rate(payment_attempts_total{{{FC},outcome="authorized",psp=~"$psp"}}[15m])) / sum(rate(payment_attempts_total{{{FC},psp=~"$psp"}}[15m]))', "now"),
                                                                           (f'100 * sum(rate(payment_attempts_total{{{FC},outcome="authorized",psp=~"$psp"}}[15m] offset 1w)) / sum(rate(payment_attempts_total{{{FC},psp=~"$psp"}}[15m] offset 1w))', "week ago")],
         "percent", lo=0, hi=100, desc="An authorization rate 5 points below the week-ago line raises AuthorizationRateDrop.")
    out.append(("l1-services", d))

    d = Dashboard("router", "Service RED: router", "l1", ["red", "router"], service="router", links=nav("platform-overview", "payments", "cells"))
    red(d, "router")
    d.row("Dependencies")
    d.ts("router: retries share by dependency, %", [(f'100 * sum by (dependency) (rate(retry_total{{{F},service=~"$service"}}[5m])) / sum by (dependency) (rate(dependency_requests_total{{{F},service=~"$service"}}[5m]))', "{{dependency}}")], "percent", lo=0, hi=100, thr=steps(10, 20),
         desc="Retry budget is 10% of the normal traffic to a dependency.")
    d.ts("router: p99 platform overhead, s", [(f'histogram_quantile(0.99, sum by (cell, le) (rate(platform_overhead_seconds_bucket{{{FC},service=~"$service"}}[5m])))', "{{cell}}")], "s", thr=steps(0.15, 0.3), exemplar=True, decimals=3)
    out.append(("l1-services", d))

    d = Dashboard("locker", "Service RED: locker (CDE)", "l1", ["red", "locker", "cde"], service="locker", links=nav("platform-overview", "payments", "cells"), description="Locker is a CDE component: no card data in any panel.")
    red(d, "locker")
    d.row("Dependencies")
    d.ts("router: retry budget exhausted for the locker, per second", [(f'sum(rate(retry_budget_exhausted_total{{{F},dependency="router-locker"}}[5m]))', "exhausted")], "ops", thr=steps(None, 0.001))
    d.ts("locker: KMS call errors, per second", [(f'sum by (operation) (rate(kms_request_errors_total{{{F},service=~"$service"}}[5m]))', "{{operation}}")], "ops")
    out.append(("l1-services", d))

    d = Dashboard("drainer", "Service RED: drainer", "l1", ["drainer", "write-behind"], service="drainer", links=nav("platform-overview", "cells", "data-stores"), description="Write-behind from the Redis stream to PostgreSQL.")
    d.row("Overview")
    d.stat("drainer: drain lag, s", f'max(drain_lag_seconds{{{FC}}})', "s", lo=0, thr=steps(T.DRAIN_LAG_S, T.DRAIN_LAG_S * 2), decimals=2, desc="Time from the write to the Redis stream to the row in PostgreSQL; the SLO is p99 5 s.")
    d.stat("drainer: Redis stream length", f'max(redis_stream_length{{{FC}}})', "short", lo=0, thr=steps(T.REDIS_STREAM_LEN / 2, T.REDIS_STREAM_LEN))
    d.stat("drainer: ready replicas", f'sum(kube_deployment_status_replicas_ready{{{F},deployment=~"drainer.*"}})', "short", lo=0)
    d.row("Throughput")
    d.ts("drainer: drain lag by cell, s", [(f'max by (cell) (drain_lag_seconds{{{FC}}})', "{{cell}}")], "s", thr=steps(T.DRAIN_LAG_S, T.DRAIN_LAG_S * 2))
    d.ts("drainer: Redis stream length by cell", [(f'max by (cell, stream) (redis_stream_length{{{FC}}})', "{{cell}} {{stream}}")], "short", thr=steps(T.REDIS_STREAM_LEN / 2, T.REDIS_STREAM_LEN))
    d.ts("drainer: rows written per second, rows/s", [(f'sum by (cell) (rate(drainer_rows_written_total{{{FC}}}[5m]))', "{{cell}}")], "ops")
    d.ts("drainer: batch write p99 duration, s", [(f'histogram_quantile(0.99, sum by (cell, le) (rate(drainer_batch_duration_seconds_bucket{{{FC}}}[5m])))', "{{cell}}")], "s", exemplar=True)
    d.row("Errors")
    d.ts("drainer: batch errors, per second", [(f'sum by (cell) (rate(drainer_batch_errors_total{{{FC}}}[5m]))', "{{cell}}")], "ops", w=24)
    out.append(("l1-services", d))

    d = Dashboard("scheduler", "Service RED: scheduler", "l1", ["scheduler", "sync"], service="scheduler", links=nav("platform-overview", "payments", "cells"), description="Sync of unknown-state payments and outgoing webhooks.")
    d.row("Overview")
    d.stat("scheduler: oldest task age, s", f'max(scheduler_queue_oldest_task_age_seconds{{{FC}}})', "s", lo=0, thr=steps(T.SCHEDULER_QUEUE_S / 2, T.SCHEDULER_QUEUE_S))
    d.stat("scheduler: unknown-state payments older than 15 min", f'sum(payments_unknown_state_stale{{{FC}}})', "short", lo=0, thr=steps(1, 100))
    d.stat("scheduler: dead-letter queue depth", f'sum(dlq_depth{{{F}}})', "short", lo=0, thr=steps(1, 100))
    d.stat("scheduler: oldest webhook age, s", f'max(webhook_queue_oldest_age_seconds{{{FC}}})', "s", lo=0, thr=steps(60, 300))
    d.row("Queues")
    d.ts("scheduler: oldest task age by cell, s", [(f'max by (cell) (scheduler_queue_oldest_task_age_seconds{{{FC}}})', "{{cell}}")], "s", thr=steps(T.SCHEDULER_QUEUE_S / 2, T.SCHEDULER_QUEUE_S))
    d.ts("scheduler: tasks processed by kind, per second", [(f'sum by (kind) (rate(scheduler_tasks_processed_total{{{FC}}}[5m]))', "{{kind}}")], "ops")
    d.row("Webhooks")
    d.ts("scheduler: webhook delivery p99, s", [(f'histogram_quantile(0.99, sum by (cell, le) (rate(webhook_delivery_seconds_bucket{{{FC}}}[5m])))', "{{cell}}")], "s", thr=steps(30, 60), exemplar=True, desc="The SLO is delivery within 60 s for 99.9% of events.")
    d.ts("scheduler: DLQ depth by queue", [(f'sum by (queue) (dlq_depth{{{F}}})', "{{queue}}")], "short", thr=steps(1, 100))
    d.row("Retries")
    d.ts("scheduler: retries share by dependency, %", [(f'100 * sum by (dependency) (rate(retry_total{{{F},service=~"$service"}}[5m])) / sum by (dependency) (rate(dependency_requests_total{{{F},service=~"$service"}}[5m]))', "{{dependency}}")], "percent", lo=0, hi=100, thr=steps(10, 20), w=24)
    out.append(("l1-services", d))

    d = Dashboard("cells", "Cells", "l2", ["cells"], links=nav("platform-overview", "payments", "data-stores"), description="Compare the 4 cells and the spare.")
    d.row("Overview")
    d.stat("cells: cache warm ratio, min %", f'100 * min(cache_warm_ratio{{{FC}}})', "percent", lo=0, hi=100, thr=steps(T.CACHE_WARM_RATIO * 100, 50, invert=True), desc="A cell takes traffic at 75% of the priority keys; a lower value after 5 minutes raises a non-paging alert.")
    d.stat("cells: HPAs at maximum", f'count(kube_horizontalpodautoscaler_status_current_replicas{{{F}}} == kube_horizontalpodautoscaler_spec_max_replicas{{{F}}}) or vector(0)', "short", lo=0, thr=steps(1, 3))
    d.stat("cells: drain lag, max s", f'max(drain_lag_seconds{{{FC}}})', "s", lo=0, thr=steps(T.DRAIN_LAG_S, T.DRAIN_LAG_S * 2))
    d.row("Traffic")
    d.ts("cells: payments per second by cell, reqps", [(f'sum by (cell) (rate(payment_attempts_total{{{FC}}}[5m]))', "{{cell}}")], "reqps")
    d.ts("cells: traffic share by cell, %", [(f'100 * sum by (cell) (rate(payment_attempts_total{{{FC}}}[5m])) / ignoring(cell) group_left sum(rate(payment_attempts_total{{{FC}}}[5m]))', "{{cell}}")], "percent", lo=0, hi=100)
    d.row("Errors")
    d.ts("router: 5xx share by cell, %", [(err_ratio().replace("$service", "router"), "{{cell}}")], "percent", lo=0, hi=100, thr=steps(T.ROUTER_5XX_RATIO * 100, 5))
    d.ts("cells: authorization rate by cell, %", [(f'100 * sum by (cell) (rate(payment_attempts_total{{{FC},outcome="authorized"}}[15m])) / sum by (cell) (rate(payment_attempts_total{{{FC}}}[15m]))', "{{cell}}")], "percent", lo=0, hi=100, thr=steps(90, 80, invert=True))
    d.row("Latency")
    d.ts("router: p99 platform overhead by cell, s", [(f'histogram_quantile(0.99, sum by (cell, le) (rate(platform_overhead_seconds_bucket{{{FC}}}[5m])))', "{{cell}}")], "s", thr=steps(0.15, 0.3), exemplar=True, decimals=3)
    d.ts("cells: cache warm ratio by cell, %", [(f'100 * min by (cell) (cache_warm_ratio{{{FC}}})', "{{cell}}")], "percent", lo=0, hi=100, thr=steps(T.CACHE_WARM_RATIO * 100, 50, invert=True))
    d.row("Resources")
    d.ts("cells: MemoryDB memory use by cell, %", [(f'100 * max by (cell) (redis_memory_used_bytes{{{FC}}} / redis_memory_max_bytes{{{FC}}})', "{{cell}}")], "percent", lo=0, hi=100, thr=steps(T.MEMORYDB_MEM_WARN * 100, T.MEMORYDB_MEM_CRIT * 100))
    d.ts("cells: HPA current replicas by cell", [(f'sum by (cell, horizontalpodautoscaler) (kube_horizontalpodautoscaler_status_current_replicas{{{FC}}})', "{{cell}} {{horizontalpodautoscaler}}")], "short", lo=0)
    out.append(("l2-platform", d))

    d = Dashboard("kubernetes", "Kubernetes (USE)", "l2", ["use", "kubernetes"], links=nav("platform-overview", "cells"), description="Is there enough capacity?")
    d.row("Overview")
    d.stat("nodes: not ready", f'count(kube_node_status_condition{{{F},condition="Ready",status="true"}} == 0) or vector(0)', "short", lo=0, thr=steps(1, 3))
    d.stat("pods: pending", f'sum(kube_pod_status_phase{{{F},phase="Pending"}})', "short", lo=0, thr=steps(1, 10))
    d.stat("subnets: lowest free IP share, %", f'100 * min(subnet_free_ip_ratio{{{F}}})', "percent", lo=0, hi=100, thr=steps(20, 10, invert=True))
    d.row("Utilization")
    d.ts("nodes: CPU use, %", [(f'100 * (1 - avg by (node) (rate(node_cpu_seconds_total{{{F},mode="idle"}}[5m])))', "{{node}}")], "percent", lo=0, hi=100, thr=steps(70, 90))
    d.ts("nodes: memory use, %", [(f'100 * (1 - node_memory_MemAvailable_bytes{{{F}}} / node_memory_MemTotal_bytes{{{F}}})', "{{node}}")], "percent", lo=0, hi=100, thr=steps(70, 90))
    d.row("Saturation")
    d.ts("pods: container restarts, per 15 min", [(f'sum by (namespace) (increase(kube_pod_container_status_restarts_total{{{F}}}[15m]))', "{{namespace}}")], "short", lo=0)
    d.ts("autoscaling: HPA replicas against the maximum", [(f'kube_horizontalpodautoscaler_status_current_replicas{{{F}}}', "{{horizontalpodautoscaler}} current"), (f'kube_horizontalpodautoscaler_spec_max_replicas{{{F}}}', "{{horizontalpodautoscaler}} max")], "short", lo=0)
    d.row("Errors")
    d.ts("karpenter: cloud provider errors, per second", [(f'sum by (method) (rate(karpenter_cloudprovider_errors_total{{{F}}}[5m]))', "{{method}}")], "ops")
    d.ts("nodes: clock offset, s", [(f'max by (node) (abs(node_timex_offset_seconds{{{F}}}))', "{{node}}")], "s", thr=steps(0.1, 0.5), decimals=3)
    out.append(("l2-platform", d))

    d = Dashboard("data-stores", "Data stores: Aurora, MemoryDB, ClickHouse, Kafka", "l3", ["data"], links=nav("platform-overview", "cells", "backup"), description="Where exactly is the bottleneck in the data tier?")
    d.row("Aurora")
    d.ts("aurora: connections share of the limit, %", [(f'100 * sum by (cell, instance) (pg_stat_database_numbackends{{{FC}}}) / max by (cell, instance) (pg_settings_max_connections{{{FC}}})', "{{cell}} {{instance}}")], "percent", lo=0, hi=100, thr=steps(T.AURORA_CONNECTIONS_RATIO * 100, 95))
    d.ts("aurora: replica lag, ms", [(f'max by (cell) (aws_rds_aurora_replica_lag_maximum{{{FC}}})', "{{cell}}")], "ms", thr=steps(T.AURORA_REPLICA_LAG_MS, T.AURORA_REPLICA_LAG_MS * 3))
    d.ts("aurora: CPU use, %", [(f'max by (cell, instance) (aws_rds_cpuutilization_average{{{FC}}})', "{{cell}} {{instance}}")], "percent", lo=0, hi=100, thr=steps(80, 95))
    d.ts("aurora: deadlocks, per second", [(f'sum by (cell) (rate(pg_stat_database_deadlocks{{{FC}}}[5m]))', "{{cell}}")], "ops")
    d.table("aurora: top 10 queries by time, ms per second", f'topk(10, sum by (cell, queryid) (rate(pg_stat_statements_total_exec_time_ms_total{{{FC}}}[5m])))', unit="ms", desc="From pg_stat_statements; queryid is a hash, not a statement text.")
    d.row("MemoryDB")
    d.ts("memorydb: memory use, %", [(f'100 * max by (cell, instance) (redis_memory_used_bytes{{{FC}}} / redis_memory_max_bytes{{{FC}}})', "{{cell}} {{instance}}")], "percent", lo=0, hi=100, thr=steps(T.MEMORYDB_MEM_WARN * 100, T.MEMORYDB_MEM_CRIT * 100))
    d.ts("memorydb: evicted keys, per second", [(f'sum by (cell) (rate(redis_evicted_keys_total{{{FC}}}[5m]))', "{{cell}}")], "ops", thr=steps(None, 0.001), desc="Any eviction is a fault: the policy is noeviction.")
    d.ts("drainer: Redis stream length by cell", [(f'max by (cell, stream) (redis_stream_length{{{FC}}})', "{{cell}} {{stream}}")], "short", thr=steps(T.REDIS_STREAM_LEN / 2, T.REDIS_STREAM_LEN))
    d.ts("drainer: drain lag by cell, s", [(f'max by (cell) (drain_lag_seconds{{{FC}}})', "{{cell}}")], "s", thr=steps(T.DRAIN_LAG_S, T.DRAIN_LAG_S * 2))
    d.row("ClickHouse, Kafka, DynamoDB, OpenSearch")
    d.ts("clickhouse: replication delay, s", [(f'max by (cluster) (ClickHouseAsyncMetrics_ReplicasMaxAbsoluteDelay{{{F}}})', "{{cluster}}")], "s", thr=steps(300, 900))
    d.ts("clickhouse: free disk, %", [(f'100 * min by (cluster, instance) (ClickHouseAsyncMetrics_DiskAvailable_default{{{F}}} / ClickHouseAsyncMetrics_DiskTotal_default{{{F}}})', "{{cluster}} {{instance}}")], "percent", lo=0, hi=100, thr=steps(20, 15, invert=True))
    d.ts("kafka: consumer group lag, messages", [(f'sum by (consumergroup, topic) (kafka_consumergroup_lag{{{F}}})', "{{consumergroup}} {{topic}}")], "short", thr=steps(50000, 100000))
    d.ts("dynamodb: throttled requests, per second", [(f'sum by (table_name) (rate(aws_dynamodb_throttled_requests_sum{{{F}}}[5m]))', "{{table_name}}")], "ops")
    d.ts("opensearch: cluster red status", [(f'max by (domain_name) (aws_es_cluster_statusred_maximum{{{F}}})', "{{domain_name}}")], "short", lo=0, hi=1, thr=steps(None, 1))
    out.append(("l3-data", d))

    d = Dashboard("backup", "Backup and restore", "l3", ["backup", "dr"], links=nav("platform-overview", "data-stores"), description="Can we restore, how fast, and how old is the newest recovery point?")
    d.row("Recovery points")
    d.stat("backup: failed jobs, 24 h", f'sum(increase(aws_backup_number_of_backup_jobs_failed_sum{{{F}}}[1d])) or vector(0)', "short", lo=0, thr=steps(None, 1))
    d.stat("restore test: stores failing", f'count(restore_test_success{{{F}}} == 0) or vector(0)', "short", lo=0, thr=steps(None, 1))
    d.stat("pitr: worst restorable time lag, s", f'max(database_latest_restorable_time_lag_seconds{{{F}}})', "s", lo=0, thr=steps(T.RESTORABLE_LAG_S / 2, T.RESTORABLE_LAG_S), desc="Data loss on a point-in-time restore is at most 5 minutes (D2).")
    d.bars("backup: age of the last successful backup by store, s", f'time() - max by (store) (backup_last_success_timestamp_seconds{{{F}}})', "{{store}}", "s", lo=0)
    d.row("Restore speed")
    d.ts("restore: duration against its target by store, s", [(f'max by (store) (backup_restore_duration_seconds{{{F}}})', "{{store}} duration"), (f'max by (store) (backup_restore_target_seconds{{{F}}})', "{{store}} target")], "s", lo=0,
         desc="Alerts fire at 80% of the target; the Aurora target is 30 minutes (D4).")
    d.ts("restore: duration share of the target by store, %", [(f'100 * max by (store) (backup_restore_duration_seconds{{{F}}}) / max by (store) (backup_restore_target_seconds{{{F}}})', "{{store}}")], "percent", lo=0, hi=150, thr=steps(T.RESTORE_TARGET_FRACTION * 100, 100))
    d.ts("restore: duration against the data size, s", [(f'max by (store) (backup_restore_duration_seconds{{{F}}})', "{{store}} duration"), (f'max by (store) (backup_source_size_bytes{{{F}}}) / 1e9', "{{store}} size, GB")], "short", lo=0, desc="Trend of the restore time against data growth.")
    d.table("restore test: last result by store", f'min by (store) (restore_test_success{{{F}}})', unit="short", w=12, desc="1 means the last daily restore passed its data check.")
    d.row("Copies")
    d.ts("snapshot copies: age of the last successful copy by region, s", [(f'time() - max by (store, region) (snapshot_copy_last_success_timestamp_seconds{{{F}}})', "{{store}} {{region}}")], "s", lo=0, thr=steps(3600, 7200))
    d.ts("backup: copy job failures, 24 h", [(f'sum by (backup_vault) (increase(aws_backup_number_of_copy_jobs_failed_sum{{{F}}}[1d]))', "{{backup_vault}}")], "short", lo=0, thr=steps(None, 1))
    out.append(("l3-data", d))

    d = Dashboard("dr-switch", "DR switch readiness", "l3", ["dr", "switch"], links=nav("platform-overview", "backup", "data-stores"), description="Recovery regions us-east-1 and us-east-2: replication, probes, test history.")
    d.row("Replication")
    d.ts("aurora global: replication lag by region, ms", [(f'max by (global_cluster, region) (aws_rds_aurora_global_db_replication_lag_maximum{{{F}}})', "{{global_cluster}} {{region}}")], "ms", thr=steps(T.AURORA_GLOBAL_LAG_MS, T.AURORA_RPO_BUDGET_MS),
         desc="Alert above 5 s; the RPO budget is 10 s (D7).")
    d.ts("dynamodb global tables: replication latency, ms", [(f'max by (table_name, receiving_region) (aws_dynamodb_replication_latency_maximum{{{F}}})', "{{table_name}} {{receiving_region}}")], "ms", thr=steps(5000, 10000))
    d.ts("s3: replication latency, s", [(f'max by (bucket, destination_region) (aws_s3_replication_latency_maximum{{{F}}})', "{{bucket}} {{destination_region}}")], "s", thr=steps(600, 900), desc="Replication Time Control target is 15 minutes.")
    d.ts("snapshot copies: age by region, s", [(f'time() - max by (store, region) (snapshot_copy_last_success_timestamp_seconds{{{F}}})', "{{store}} {{region}}")], "s", lo=0, thr=steps(3600, 7200))
    d.row("Detection")
    d.ts("probes: region health from each probe point", [(f'min by (probe_point) (probe_success{{env=~"$env",probe_target="region-health"}})', "{{probe_point}}")], "short", lo=0, hi=1, thr=steps(1, None, invert=True),
         desc="The switch is proposed when two of three independent points fail.")
    d.ts("synthetic payment: success by probe point", [(f'min by (probe_point) (synthetic_payment_success{{env=~"$env"}})', "{{probe_point}}")], "short", lo=0, hi=1, thr=steps(1, None, invert=True))
    d.row("Test history")
    d.stat("dr test: days since the last full switch test", f'(time() - max(dr_switch_test_last_success_timestamp_seconds{{env=~"$env"}})) / 86400', "d", lo=0, thr=steps(92, 100), decimals=0, desc="The test is quarterly, to us-east-1 and us-east-2 in turn.")
    d.stat("dr test: last switch duration, min", f'max(dr_switch_test_duration_seconds{{env=~"$env"}}) / 60', "m", lo=0, thr=steps(60, 75), decimals=0, desc="RTO target 60 minutes, 75 in plan B.")
    d.stat("dr: cache warm ratio, min %", f'100 * min(cache_warm_ratio{{{F}}})', "percent", lo=0, hi=100, thr=steps(T.CACHE_WARM_RATIO * 100, 50, invert=True))
    out.append(("l3-data", d))

    d = Dashboard("edge", "Edge and security", "l3", ["edge", "security"], links=nav("platform-overview", "kubernetes"), description="What happens at the entrance?")
    d.row("Overview")
    d.stat("edge: certificates expiring within 30 days", f'count((min by (target) (probe_ssl_earliest_cert_expiry{{env=~"$env"}}) - time()) < 30 * 86400) or vector(0)', "short", lo=0, thr=steps(1, 3))
    d.stat("security: events in the last hour", 'sum(increase(security_events_total{env=~"$env"}[1h])) or vector(0)', "short", lo=0, thr=steps(1, 5))
    d.stat("security: PAN detections, 24 h", 'sum(increase(pan_detected_total{env=~"$env"}[1d])) or vector(0)', "short", lo=0, thr=steps(None, 1))
    d.row("Traffic")
    d.ts("edge: rate-limited responses (429), reqps", [(f'sum by (cell) (rate(http_server_requests_total{{{FC},service="router",code="429"}}[5m]))', "{{cell}}")], "reqps")
    d.ts("waf: blocked requests, reqps", [(f'sum by (web_acl) (rate(aws_wafv2_blocked_requests_sum{{{F}}}[5m]))', "{{web_acl}}")], "reqps", thr=steps(50, 100))
    d.row("Network")
    d.ts("egress: NAT port allocation errors, per second", [(f'sum by (nat_gateway_id) (rate(aws_natgateway_error_port_allocation_sum{{{F}}}[5m]))', "{{nat_gateway_id}}")], "ops", thr=steps(None, 0.001))
    d.ts("egress: firewall dropped packets, pps", [(f'sum by (firewall) (rate(aws_networkfirewall_dropped_packets_sum{{{F}}}[5m]))', "{{firewall}}")], "pps", thr=steps(500, 1000))
    d.ts("edge: certificate days left by target", [(f'(min by (target) (probe_ssl_earliest_cert_expiry{{env=~"$env"}}) - time()) / 86400', "{{target}}")], "d", lo=0, thr=steps(30, 14, invert=True))
    d.ts("edge: CloudFront 5xx share, %", [(f'max by (distribution) (aws_cloudfront_5xx_error_rate_average{{{F}}})', "{{distribution}}")], "percent", lo=0, hi=100, thr=steps(2, 5))
    d.row("Security")
    d.ts("security: events by kind, per hour", [('sum by (event) (increase(security_events_total{env=~"$env"}[1h]))', "{{event}}")], "short", lo=0)
    d.ts("guardduty: findings by severity, per hour", [('sum by (severity) (increase(guardduty_findings_total{env=~"$env"}[1h]))', "{{severity}}")], "short", lo=0)
    out.append(("l3-edge", d))

    d = Dashboard("cost", "FinOps", "finops", ["finops", "cost"], links=nav("platform-overview", "cells"), description="How much do 1000 payments cost?")
    d.row("Unit cost")
    d.stat("finops: cost per 1000 payments, USD", 'sum(finops_cost_usd_per_day{env=~"$env"}) / (sum(increase(payment_attempts_total{env=~"$env"}[1d])) / 1000)', "currencyUSD", lo=0, decimals=3)
    d.stat("finops: spend this month, USD", 'sum(finops_cost_usd_month_to_date{env=~"$env"})', "currencyUSD", lo=0, decimals=0)
    d.stat("finops: budget used, %", '100 * sum(finops_cost_usd_month_to_date{env=~"$env"}) / sum(finops_budget_usd_month{env=~"$env"})', "percent", lo=0, hi=120, thr=steps(80, 100))
    d.row("Spend")
    d.bars("finops: daily spend by component, USD", 'sum by (component) (finops_cost_usd_per_day{env=~"$env"})', "{{component}}", "currencyUSD", lo=0)
    d.ts("finops: daily spend by component, USD", [('sum by (component) (finops_cost_usd_per_day{env=~"$env"})', "{{component}}")], "currencyUSD", lo=0)
    d.ts("finops: spot interruptions, per hour", [('sum(increase(karpenter_interruption_received_messages_total{env=~"$env"}[1h]))', "interruptions")], "short", lo=0)
    out.append(("finops", d))
    return out
