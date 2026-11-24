"""Dashboard definitions by level (section 15 hierarchy); thresholds come from thresholds.py."""
import thresholds as T
from panels import F, FC, Dashboard, drill, steps

TITLES = {
    "platform-overview": "L0 Platform overview", "slo-overview": "L0 SLO overview", "payments": "L1 Payments and PSP health", "router": "L1 Router (RED)",
    "locker": "L1 Locker (RED, CDE)", "drainer": "L1 Drainer (write-behind)", "scheduler": "L1 Scheduler (sync and webhooks)", "cells": "L2 Cells",
    "kubernetes": "L2 Kubernetes (USE)", "data-stores": "L3 Data stores", "backup": "L3 Backup and restore", "dr-switch": "L3 DR switch readiness",
    "edge": "L3 Edge and security", "cost": "FinOps: unit cost and spend",
}
# cAdvisor also exports a pod-level series with an empty container; counting it doubles the use.
CADVISOR_CONTAINERS = 'container!="",container!="POD"'


def nav(*uids):
    return [(u, TITLES[u]) for u in uids]


def to(uid, var=None):
    return drill(uid, TITLES[uid], var)


def ratio(num, den):
    # An empty denominator yields no data instead of NaN or a division by zero.
    return f"{num} / ({den} > 0)"


def top(expr, k=8):
    return f"topk({k}, {expr})"


def bottom(expr, k=8):
    return f"bottomk({k}, {expr})"


def requests(by, extra=""):
    return f'sum{by} (rate(http_server_requests_total{{{FC},service=~"$service"{extra}}}[5m]))'


def err_ratio(by=" by (cell)", extra=""):
    return "100 * " + ratio(requests(by, extra + ',code=~"5.."'), requests(by, extra))


def auth_rate(by="", sel=FC, extra=""):
    b = f" by ({by})" if by else ""
    return "100 * " + ratio(f'sum{b} (rate(payment_attempts_total{{{sel},outcome="authorized"{extra}}}[15m]))', f"sum{b} (rate(payment_attempts_total{{{sel}{extra}}}[15m]))")


def quantile(q, metric, by="cell", extra=""):
    return f'histogram_quantile({q}, sum by ({by}, le) (rate({metric}_bucket{{{FC},service=~"$service"{extra}}}[5m])))'


AUTH_THR = steps(90, 80, invert=True)
OVERHEAD_THR = steps(0.15, 0.3)


def red(d, name, err_thr):
    d.row("Overview")
    d.stat(f"{name}: requests per second", requests(""), "reqps", thr=steps(info=True), decimals=1)
    d.stat(f"{name}: 5xx share", err_ratio(""), "percent", hi=100, thr=err_thr, decimals=2)
    d.stat(f"{name}: p99 latency", quantile(0.99, "http_server_request_duration_seconds", by="service"), "s", thr=steps(0.3, 1), decimals=3)
    d.stat(f"{name}: ready replicas", f'sum(kube_deployment_status_replicas_ready{{{F},deployment=~"$service.*"}})', "short", thr=steps(None, 1, invert=True),
           desc="Pods ready to take traffic; red at zero.")
    d.row("Traffic")
    d.ts(f"{name}: requests per second by cell, reqps", [(requests(" by (cell)"), "{{cell}}")], "reqps", link=to("cells", "cell"))
    d.ts(f"{name}: requests per second by status code, reqps", [(requests(" by (code)"), "{{code}}")], "reqps")
    d.row("Errors")
    d.ts(f"{name}: 5xx share by cell, %", [(err_ratio(), "{{cell}}")], "percent", hi=100, thr=err_thr, w=24, link=to("cells", "cell"))
    d.row("Latency")
    d.ts(f"{name}: p50, p95, p99 latency, s", [(quantile(q, "http_server_request_duration_seconds", by="service"), f"p{int(q * 100)}") for q in (0.5, 0.95, 0.99)], "s",
         exemplar=True, desc="Exemplars link a latency peak to a trace in Tempo.")
    d.heatmap(f"{name}: latency distribution, s", f'sum by (le) (increase(http_server_request_duration_seconds_bucket{{{FC},service=~"$service"}}[5m]))',
              desc="Requests per latency bucket; a second band means a slow path.")
    d.row("Resources")
    d.ts(f"{name}: CPU use, % of limit (top 8 pods)", [(top("100 * " + ratio(f'sum by (pod) (rate(container_cpu_usage_seconds_total{{{F},{CADVISOR_CONTAINERS},pod=~"$service.*"}}[5m]))',
                                                                            f'sum by (pod) (kube_pod_container_resource_limits{{{F},pod=~"$service.*",resource="cpu"}})')), "{{pod}}")],
         "percent", hi=100, thr=steps(70, 90))
    d.ts(f"{name}: memory working set (top 8 pods), bytes", [(top(f'sum by (pod) (container_memory_working_set_bytes{{{F},{CADVISOR_CONTAINERS},pod=~"$service.*"}})'), "{{pod}}")], "bytes")


def retries(d, w=12):
    d.ts("retries: share of the traffic by dependency, %", [("100 * " + ratio(f'sum by (dependency) (rate(retry_total{{{F},service=~"$service"}}[5m]))',
                                                                           f'sum by (dependency) (rate(dependency_requests_total{{{F},service=~"$service"}}[5m]))'), "{{dependency}}")],
         "percent", hi=100, thr=steps(T.RETRY_RATIO * 100), w=w, desc="Retry budget is 10% of the normal traffic to a dependency; above it RetryStorm fires.")


def drain_lag_ts(d):
    d.ts("drainer: drain lag by cell, s", [(f'max by (cell) (drain_lag_seconds{{{FC}}})', "{{cell}}")], "s", thr=steps(T.DRAIN_LAG_S / 2, T.DRAIN_LAG_S), link=to("drainer", "cell"))


def stream_ts(d):
    d.ts("drainer: Redis stream length (top 8), entries", [(top(f'max by (cell, stream) (redis_stream_length{{{FC}}})'), "{{cell}} {{stream}}")], "short",
         thr=steps(T.REDIS_STREAM_LEN / 2, T.REDIS_STREAM_LEN))


DRAIN_THR = steps(T.DRAIN_LAG_S / 2, T.DRAIN_LAG_S)
STALE_DESC = "Payments in an unknown state for more than 15 minutes; the scheduler syncs them with the PSP."


def build_all():
    out = []

    d = Dashboard("platform-overview", TITLES["platform-overview"], "l0", ["overview"], links=nav("slo-overview", "payments", "cells"), runbooks=["meta", "slo"],
                  description="Are payments going through right now?")
    d.row("Overview")
    d.stat("platform: authorization rate", auth_rate(), "percent", hi=100, thr=AUTH_THR, decimals=2, link=to("payments"),
           desc="Share of successful authorizations among all payment attempts of the last 15 minutes.")
    d.stat("platform: payments per second", f'sum(rate(payment_attempts_total{{{FC}}}[5m]))', "reqps", decimals=0)
    d.stat("SLO: authorization budget left", f'100 * min(slo:period_error_budget_remaining:ratio{{{F},sloth_id="payments-authorization-availability"}})', "percent", hi=100,
           thr=steps(50, 20, invert=True), link=to("slo-overview"), desc="Error budget of the 99.99% authorization SLO left in the 30-day period, worst region.")
    d.stat("platform: critical alerts firing", 'count(ALERTS{alertstate="firing",severity=~"critical|security",env=~"$env"}) or vector(0)', "short", thr=steps(None, 1))
    d.stat("drainer: drain lag", f'max(drain_lag_seconds{{{FC}}})', "s", thr=DRAIN_THR, link=to("drainer"), desc="Redis stream to PostgreSQL; DrainLagHigh pages above 5 s.")
    d.stat("scheduler: stale unknown-state", f'sum(payments_unknown_state_stale{{{FC}}})', "short", thr=steps(1), link=to("scheduler"), desc=STALE_DESC)
    d.row("Traffic")
    d.ts("platform: payments per second by cell, reqps", [(f'sum by (cell) (rate(payment_attempts_total{{{FC}}}[5m]))', "{{cell}}")], "reqps", link=to("cells", "cell"))
    d.ts("platform: authorization rate by cell, %", [(auth_rate("cell"), "{{cell}}")], "percent", hi=100, thr=AUTH_THR, link=to("cells", "cell"))
    d.row("Errors")
    d.ts("router: 5xx share by cell, %", [(err_ratio().replace("$service", "router"), "{{cell}}")], "percent", hi=100, thr=steps(T.ROUTER_5XX_RATIO * 100), w=24, link=to("router", "cell"))
    d.row("Latency")
    d.ts("router: p99 platform overhead by cell, s", [(f'histogram_quantile(0.99, sum by (cell, le) (rate(platform_overhead_seconds_bucket{{{FC}}}[5m])))', "{{cell}}")], "s",
         thr=OVERHEAD_THR, exemplar=True, decimals=3, w=24, link=to("router", "cell"), desc="Platform time on top of the PSP time; the SLO is 150 ms at p99.")
    out.append(("l0-overview", d))

    d = Dashboard("slo-overview", TITLES["slo-overview"], "l0", ["slo"], links=nav("platform-overview", "payments"), runbooks=["slo"],
                  description="How much budget is left and how fast it burns.")
    slos = [("payments-authorization-availability", "authorization", "99.99%"), ("payments-platform-overhead-latency", "platform overhead", "99.9%"),
            ("payments-status-read", "status read", "99.95%"), ("payments-webhooks-delivery", "webhook delivery", "99.9%")]
    d.row("Error budget left")
    for sid, name, target in slos:
        d.gauge(f"SLO: {name} budget left", f'100 * min(slo:period_error_budget_remaining:ratio{{{F},sloth_id="{sid}"}})', "percent", 0, 100, steps(50, 20, invert=True),
                desc=f"Share of the 30-day error budget of the {target} SLO still left, worst region.")
    d.row("Burn rate")
    burn = '/ on(env, region, sloth_id, sloth_slo, sloth_service) group_left() slo:error_budget:ratio'
    legend = "{{sloth_id}} {{region}}"
    d.ts("SLO: burn rate over 1 h, x budget", [(f'slo:sli_error:ratio_rate1h{{{F}}} {burn}', legend)], "none", thr=steps(6, 14.4),
         desc="1 means the budget lasts exactly the period; 14.4 with the 5-minute window pages (2% of the budget per hour).")
    d.ts("SLO: burn rate over 6 h, x budget", [(f'slo:sli_error:ratio_rate6h{{{F}}} {burn}', legend)], "none", thr=steps(1, 6), desc="6 pages with the 30-minute window; 1 opens a ticket with the 3-day window.")
    d.ts("SLO: burn rate over 5 min, x budget", [(f'slo:sli_error:ratio_rate5m{{{F}}} {burn}', legend)], "none", thr=steps(14.4, 50), desc="50 pages for the 99.99% authorization SLO.")
    d.ts("SLO: burn rate over 3 days, x budget", [(f'slo:sli_error:ratio_rate3d{{{F}}} {burn}', legend)], "none", thr=steps(1), desc="Above 1 with the 6-hour window opens a ticket.")
    out.append(("l0-overview", d))

    d = Dashboard("payments", TITLES["payments"], "l1", ["psp", "payments"], links=nav("platform-overview", "slo-overview", "cells"), runbooks=["application"],
                  description="Which PSP degrades?")
    psp = ',psp=~"$psp"'
    d.row("Overview")
    d.stat("payments: authorization rate", auth_rate(extra=psp), "percent", hi=100, thr=AUTH_THR, decimals=2, desc="Successful authorizations among all attempts of the last 15 minutes.")
    d.stat("scheduler: stale unknown-state", f'sum(payments_unknown_state_stale{{{FC}}})', "short", thr=steps(1), link=to("scheduler"), desc=STALE_DESC)
    d.stat("router: PSP breakers open", f'count(max by (psp) (circuit_breaker_state{{{F},dependency="psp-authorize"{psp}}}) == 2) or vector(0)', "short", thr=steps(1),
           desc="PSPs whose authorize circuit breaker is open on at least one pod.")
    d.stat("reconciliation: mismatches, 24 h", f'sum(increase(reconciliation_amount_mismatch_total{{{F}{psp}}}[1d])) or vector(0)', "short", thr=steps(1),
           desc="Payments whose amount differs between the platform and the PSP settlement report.")
    d.row("PSP")
    d.bars("router: authorization rate by PSP, %", auth_rate("psp", extra=psp), "{{psp}}", "percent", hi=100, thr=AUTH_THR)
    d.ts("router: PSP technical error share, %", [("100 * " + ratio(f'sum by (psp) (rate(psp_requests_total{{{FC},outcome="technical_error"{psp}}}[5m]))',
                                                                 f'sum by (psp) (rate(psp_requests_total{{{FC}{psp}}}[5m]))'), "{{psp}}")], "percent", hi=100,
         thr=steps(T.PSP_ERROR_RATIO * 50, T.PSP_ERROR_RATIO * 100), desc="PSPDegraded pages above 5%.")
    d.ts("router: PSP p99 latency, s", [(f'histogram_quantile(0.99, sum by (psp, le) (rate(psp_request_duration_seconds_bucket{{{FC}{psp}}}[5m])))', "{{psp}}")], "s",
         thr=steps(T.PSP_P99_S), exemplar=True)
    d.heatmap("router: PSP call latency distribution, s", f'sum by (le) (increase(psp_request_duration_seconds_bucket{{{FC}{psp}}}[5m]))')
    d.row("Attempts")
    d.ts("router: payment attempts by outcome, reqps", [(f'sum by (outcome) (rate(payment_attempts_total{{{FC}{psp}}}[5m]))', "{{outcome}}")], "reqps")
    week = auth_rate(extra=psp).replace("[15m]", "[15m] offset 1w")
    d.ts("router: authorization rate against last week, %", [(auth_rate(extra=psp), "now"), (week, "week ago")], "percent", hi=100,
         desc="An authorization rate 5 points below the week-ago line raises AuthorizationRateDrop.")
    out.append(("l1-services", d))

    d = Dashboard("router", TITLES["router"], "l1", ["red", "router"], service="router", links=nav("platform-overview", "payments", "cells"), runbooks=["application"],
                  description="Rate, errors and duration of the payment API.")
    red(d, "router", steps(T.ROUTER_5XX_RATIO * 100))
    d.row("Dependencies")
    retries(d)
    d.ts("router: p99 platform overhead by cell, s", [(f'histogram_quantile(0.99, sum by (cell, le) (rate(platform_overhead_seconds_bucket{{{FC},service=~"$service"}}[5m])))', "{{cell}}")],
         "s", thr=OVERHEAD_THR, exemplar=True, decimals=3, desc="Platform time on top of the PSP time; the SLO is 150 ms at p99.")
    out.append(("l1-services", d))

    d = Dashboard("locker", TITLES["locker"], "l1", ["red", "locker", "cde"], service="locker", links=nav("platform-overview", "payments", "cells"), runbooks=["application"],
                  description="Locker is a CDE component: no card data in any panel.")
    red(d, "locker", steps(None, T.LOCKER_5XX_RATIO * 100))
    d.row("Dependencies")
    d.ts("router: retry budget exhausted towards the locker, per second", [(f'sum(rate(retry_budget_exhausted_total{{{F},dependency="router-locker"}}[5m]))', "exhausted")], "ops",
         thr=steps(None, 0.001), desc="Any exhaustion pages: the router stops retrying the locker.")
    d.ts("locker: KMS call errors, per second", [(f'sum by (operation) (rate(kms_request_errors_total{{{F},service=~"$service"}}[5m]))', "{{operation}}")], "ops")
    out.append(("l1-services", d))

    d = Dashboard("drainer", TITLES["drainer"], "l1", ["drainer", "write-behind"], service="drainer", links=nav("platform-overview", "cells", "data-stores"), runbooks=["application"],
                  description="Write-behind from the Redis stream to PostgreSQL.")
    d.row("Overview")
    d.stat("drainer: drain lag", f'max(drain_lag_seconds{{{FC}}})', "s", thr=DRAIN_THR, desc="Time from the write to the Redis stream to the row in PostgreSQL; the SLO is p99 5 s.")
    d.stat("drainer: Redis stream length", f'max(redis_stream_length{{{FC}}})', "short", thr=steps(T.REDIS_STREAM_LEN / 2, T.REDIS_STREAM_LEN), desc="Longest stream; RedisStreamBacklog pages above 50 000.")
    d.stat("drainer: ready replicas", f'sum(kube_deployment_status_replicas_ready{{{F},deployment=~"drainer.*"}})', "short", thr=steps(None, 1, invert=True), desc="Pods ready to drain; red at zero.")
    d.row("Throughput")
    d.ts("drainer: rows written per second by cell, rows/s", [(f'sum by (cell) (rate(drainer_rows_written_total{{{FC}}}[5m]))', "{{cell}}")], "ops")
    stream_ts(d)
    d.row("Errors")
    d.ts("drainer: batch errors per second by cell", [(f'sum by (cell) (rate(drainer_batch_errors_total{{{FC}}}[5m]))', "{{cell}}")], "ops", w=24)
    d.row("Latency")
    drain_lag_ts(d)
    d.ts("drainer: batch write p99 duration by cell, s", [(f'histogram_quantile(0.99, sum by (cell, le) (rate(drainer_batch_duration_seconds_bucket{{{FC}}}[5m])))', "{{cell}}")], "s", exemplar=True)
    out.append(("l1-services", d))

    d = Dashboard("scheduler", TITLES["scheduler"], "l1", ["scheduler", "sync"], service="scheduler", links=nav("platform-overview", "payments", "cells"), runbooks=["application"],
                  description="Sync of unknown-state payments and outgoing webhooks.")
    d.row("Overview")
    d.stat("scheduler: oldest task age", f'max(scheduler_queue_oldest_task_age_seconds{{{FC}}})', "s", thr=steps(T.SCHEDULER_QUEUE_S / 2, T.SCHEDULER_QUEUE_S),
           desc="SchedulerQueueDelayHigh pages above 10 minutes.")
    d.stat("scheduler: stale unknown-state", f'sum(payments_unknown_state_stale{{{FC}}})', "short", thr=steps(1), desc=STALE_DESC)
    d.stat("scheduler: dead-letter queue depth", f'sum(dlq_depth{{{F}}})', "short", thr=steps(1), desc="Tasks that exhausted their retries; any entry needs a look.")
    d.stat("scheduler: oldest webhook age", f'max(webhook_queue_oldest_age_seconds{{{FC}}})', "s", thr=steps(T.WEBHOOK_AGE_S), desc="The delivery SLO is 60 s; WebhookBacklogOld warns above 5 minutes.")
    d.row("Queues")
    d.ts("scheduler: oldest task age by cell, s", [(f'max by (cell) (scheduler_queue_oldest_task_age_seconds{{{FC}}})', "{{cell}}")], "s", thr=steps(T.SCHEDULER_QUEUE_S / 2, T.SCHEDULER_QUEUE_S))
    d.ts("scheduler: tasks processed per second by kind", [(f'sum by (kind) (rate(scheduler_tasks_processed_total{{{FC}}}[5m]))', "{{kind}}")], "ops")
    d.row("Webhooks")
    d.ts("scheduler: webhook delivery p99 by cell, s", [(f'histogram_quantile(0.99, sum by (cell, le) (rate(webhook_delivery_seconds_bucket{{{FC}}}[5m])))', "{{cell}}")], "s",
         thr=steps(30, 60), exemplar=True, desc="The SLO is delivery within 60 s for 99.9% of events.")
    d.ts("scheduler: dead-letter queue depth by queue", [(top(f'sum by (queue) (dlq_depth{{{F}}})'), "{{queue}}")], "short", thr=steps(1))
    d.row("Retries")
    retries(d, w=24)
    out.append(("l1-services", d))

    d = Dashboard("cells", TITLES["cells"], "l2", ["cells"], links=nav("platform-overview", "payments", "data-stores"), runbooks=["application", "data"],
                  description="Compare the 4 cells and the spare.")
    d.row("Overview")
    d.stat("cells: lowest cache warm ratio", f'100 * min(cache_warm_ratio{{{FC}}})', "percent", hi=100, thr=steps(T.CACHE_WARM_RATIO * 100, invert=True),
           desc="A cell takes traffic at 75% of the priority keys; a lower value after 5 minutes raises a non-paging alert.")
    d.stat("cells: HPAs at maximum", f'count(kube_horizontalpodautoscaler_status_current_replicas{{{F}}} == kube_horizontalpodautoscaler_spec_max_replicas{{{F}}}) or vector(0)', "short",
           thr=steps(1), link=to("kubernetes"), desc="Autoscalers that cannot add replicas any more.")
    d.stat("cells: worst drain lag", f'max(drain_lag_seconds{{{FC}}})', "s", thr=DRAIN_THR, link=to("drainer"))
    d.row("Traffic")
    d.ts("cells: payments per second by cell, reqps", [(f'sum by (cell) (rate(payment_attempts_total{{{FC}}}[5m]))', "{{cell}}")], "reqps", link=to("router", "cell"))
    d.ts("cells: traffic share by cell, %", [(f'100 * sum by (cell) (rate(payment_attempts_total{{{FC}}}[5m])) / ignoring(cell) group_left (sum(rate(payment_attempts_total{{{FC}}}[5m])) > 0)', "{{cell}}")], "percent", hi=100)
    d.row("Errors")
    d.ts("router: 5xx share by cell, %", [(err_ratio().replace("$service", "router"), "{{cell}}")], "percent", hi=100, thr=steps(T.ROUTER_5XX_RATIO * 100), link=to("router", "cell"))
    d.ts("cells: authorization rate by cell, %", [(auth_rate("cell"), "{{cell}}")], "percent", hi=100, thr=AUTH_THR, link=to("payments"))
    d.row("Latency")
    d.ts("router: p99 platform overhead by cell, s", [(f'histogram_quantile(0.99, sum by (cell, le) (rate(platform_overhead_seconds_bucket{{{FC}}}[5m])))', "{{cell}}")], "s",
         thr=OVERHEAD_THR, exemplar=True, decimals=3, link=to("router", "cell"))
    d.ts("cells: cache warm ratio by cell, %", [(f'100 * min by (cell) (cache_warm_ratio{{{FC}}})', "{{cell}}")], "percent", hi=100, thr=steps(T.CACHE_WARM_RATIO * 100, invert=True))
    d.row("Resources")
    d.ts("cells: MemoryDB memory use by cell, %", [(f'100 * max by (cell) (redis_memory_used_bytes{{{FC}}} / redis_memory_max_bytes{{{FC}}})', "{{cell}}")], "percent", hi=100,
         thr=steps(T.MEMORYDB_MEM_WARN * 100, T.MEMORYDB_MEM_CRIT * 100), link=to("data-stores", "cell"))
    d.ts("cells: HPA replicas (top 8), replicas", [(top(f'sum by (cell, horizontalpodautoscaler) (kube_horizontalpodautoscaler_status_current_replicas{{{FC}}})'),
                                                    "{{cell}} {{horizontalpodautoscaler}}")], "short")
    out.append(("l2-platform", d))

    d = Dashboard("kubernetes", TITLES["kubernetes"], "l2", ["use", "kubernetes"], links=nav("platform-overview", "cells"), runbooks=["compute"], description="Is there enough capacity?")
    d.row("Overview")
    d.stat("nodes: not ready", f'count(kube_node_status_condition{{{F},condition="Ready",status="true"}} == 0) or vector(0)', "short", thr=steps(1))
    d.stat("pods: pending", f'sum(kube_pod_status_phase{{{F},phase="Pending"}})', "short", thr=steps(1))
    d.stat("subnets: lowest free IP share", f'100 * min(subnet_free_ip_ratio{{{F}}})', "percent", hi=100, thr=steps(T.SUBNET_FREE_IP_RATIO * 100, invert=True),
           desc="Pods and nodes take IPs from these subnets; SubnetFreeIpsLow warns below 20%.")
    d.row("Utilization")
    d.ts("nodes: CPU use (top 8 nodes), %", [(top(f'100 * (1 - avg by (node) (rate(node_cpu_seconds_total{{{F},mode="idle"}}[5m])))'), "{{node}}")], "percent", hi=100, thr=steps(70, 90))
    d.ts("nodes: memory use (top 8 nodes), %", [(top(f'100 * (1 - node_memory_MemAvailable_bytes{{{F}}} / node_memory_MemTotal_bytes{{{F}}})'), "{{node}}")], "percent", hi=100, thr=steps(70, 90))
    d.row("Saturation")
    d.ts("pods: container restarts per 15 min (top 8 namespaces)", [(top(f'sum by (namespace) (increase(kube_pod_container_status_restarts_total{{{F}}}[15m]))'), "{{namespace}}")], "short")
    d.ts("autoscaling: HPA replicas, % of the maximum (top 8)", [(top("100 * " + ratio(f'max by (namespace, horizontalpodautoscaler) (kube_horizontalpodautoscaler_status_current_replicas{{{F}}})',
                                                                                    f'max by (namespace, horizontalpodautoscaler) (kube_horizontalpodautoscaler_spec_max_replicas{{{F}}})')),
                                                                 "{{namespace}} {{horizontalpodautoscaler}}")], "percent", hi=100, thr=steps(100), desc="HpaAtMaxReplicas warns at 100%.")
    d.row("Errors")
    d.ts("karpenter: cloud provider errors per second by method", [(f'sum by (method) (rate(karpenter_cloudprovider_errors_total{{{F}}}[5m]))', "{{method}}")], "ops",
         desc="Create errors page when more than 5 happen in 15 minutes.")
    d.ts("nodes: clock offset (top 8 nodes), s", [(top(f'max by (node) (abs(node_timex_offset_seconds{{{F}}}))'), "{{node}}")], "s", thr=steps(T.CLOCK_DRIFT_S), decimals=3)
    out.append(("l2-platform", d))

    d = Dashboard("data-stores", TITLES["data-stores"], "l3", ["data"], links=nav("platform-overview", "cells", "backup"), runbooks=["data"],
                  description="Aurora, MemoryDB, ClickHouse, Kafka, DynamoDB and OpenSearch: where exactly is the bottleneck in the data tier?")
    conn = "100 * " + ratio(f'sum by (cell, instance) (pg_stat_database_numbackends{{{FC}}})', f'max by (cell, instance) (pg_settings_max_connections{{{FC}}})')
    mem = f'100 * max by (cell, instance) (redis_memory_used_bytes{{{FC}}} / redis_memory_max_bytes{{{FC}}})'
    kafka = f'sum by (consumergroup, topic) (kafka_consumergroup_lag{{{F}}})'
    d.row("Overview")
    d.stat("aurora: worst connection use", f"max({conn})", "percent", hi=100, thr=steps(T.AURORA_CONNECTIONS_RATIO * 100))
    d.stat("aurora: worst replica lag", f'max(aws_rds_aurora_replica_lag_maximum{{{FC}}})', "ms", thr=steps(T.AURORA_REPLICA_LAG_MS), decimals=0)
    d.stat("memorydb: worst memory use", f"max({mem})", "percent", hi=100, thr=steps(T.MEMORYDB_MEM_WARN * 100, T.MEMORYDB_MEM_CRIT * 100))
    d.stat("memorydb: evicted keys, 15 min", f'sum(increase(redis_evicted_keys_total{{{FC}}}[15m])) or vector(0)', "short", thr=steps(None, 1), desc="Any eviction is a fault: the policy is noeviction.")
    d.stat("kafka: worst consumer lag", f"max({kafka})", "short", thr=steps(T.KAFKA_LAG))
    d.stat("opensearch: domains in red", f'count(max by (domain_name) (aws_es_cluster_statusred_maximum{{{F}}}) >= 1) or vector(0)', "short", thr=steps(None, 1))
    d.row("Aurora")
    d.ts("aurora: connections, % of the limit (top 8)", [(top(conn), "{{cell}} {{instance}}")], "percent", hi=100, thr=steps(T.AURORA_CONNECTIONS_RATIO * 100))
    d.ts("aurora: replica lag by cell, ms", [(f'max by (cell) (aws_rds_aurora_replica_lag_maximum{{{FC}}})', "{{cell}}")], "ms", thr=steps(T.AURORA_REPLICA_LAG_MS))
    d.ts("aurora: CPU use (top 8 instances), %", [(top(f'max by (cell, instance) (aws_rds_cpuutilization_average{{{FC}}})'), "{{cell}} {{instance}}")], "percent", hi=100, thr=steps(T.AURORA_CPU_PCT))
    d.ts("aurora: deadlocks per second by cell", [(f'sum by (cell) (rate(pg_stat_database_deadlocks{{{FC}}}[5m]))', "{{cell}}")], "ops")
    d.table("aurora: top 10 queries by execution time, ms per second", f'topk(10, sum by (cell, queryid) (rate(pg_stat_statements_total_exec_time_ms_total{{{FC}}}[5m])))', unit="ms",
            value_name="ms per second", desc="From pg_stat_statements; queryid is a hash, not a statement text.")
    d.row("MemoryDB")
    d.ts("memorydb: memory use (top 8 nodes), %", [(top(mem), "{{cell}} {{instance}}")], "percent", hi=100, thr=steps(T.MEMORYDB_MEM_WARN * 100, T.MEMORYDB_MEM_CRIT * 100))
    d.ts("memorydb: evicted keys per second by cell", [(f'sum by (cell) (rate(redis_evicted_keys_total{{{FC}}}[5m]))', "{{cell}}")], "ops", thr=steps(None, 0.001),
         desc="Any eviction is a fault: the policy is noeviction.")
    stream_ts(d)
    drain_lag_ts(d)
    d.row("ClickHouse, Kafka, DynamoDB, OpenSearch")
    d.ts("clickhouse: replication delay by cluster, s", [(f'max by (cluster) (ClickHouseAsyncMetrics_ReplicasMaxAbsoluteDelay{{{F}}})', "{{cluster}}")], "s", thr=steps(T.CLICKHOUSE_DELAY_S))
    d.ts("clickhouse: free disk (lowest 8), %", [(bottom(f'100 * min by (cluster, instance) (ClickHouseAsyncMetrics_DiskAvailable_default{{{F}}} / ClickHouseAsyncMetrics_DiskTotal_default{{{F}}})'),
                                                  "{{cluster}} {{instance}}")], "percent", hi=100, thr=steps(T.CLICKHOUSE_DISK_FREE_RATIO * 100, invert=True))
    d.ts("kafka: consumer group lag (top 8), messages", [(top(kafka), "{{consumergroup}} {{topic}}")], "short", thr=steps(T.KAFKA_LAG))
    d.ts("dynamodb: throttled requests per second (top 8 tables)", [(top(f'sum by (table_name) (rate(aws_dynamodb_throttled_requests_sum{{{F}}}[5m]))'), "{{table_name}}")], "ops")
    d.ts("opensearch: cluster status red, 1 = red", [(f'max by (domain_name) (aws_es_cluster_statusred_maximum{{{F}}})', "{{domain_name}}")], "short", hi=1, thr=steps(None, 1))
    out.append(("l3-data", d))

    d = Dashboard("backup", TITLES["backup"], "l3", ["backup", "dr"], links=nav("platform-overview", "data-stores", "dr-switch"), runbooks=["backup-dr"], time=("now-7d", "5m"),
                  description="Can we restore, how fast, and how old is the newest recovery point?")
    d.row("Recovery points")
    d.stat("backup: failed jobs, 24 h", f'sum(increase(aws_backup_number_of_backup_jobs_failed_sum{{{F}}}[1d])) or vector(0)', "short", thr=steps(None, 1))
    d.stat("restore test: stores failing", f'count(restore_test_success{{{F}}} == 0) or vector(0)', "short", thr=steps(None, 1), desc="Stores whose last daily restore failed its data check.")
    d.stat("PITR: worst restorable time lag", f'max(database_latest_restorable_time_lag_seconds{{{F}}})', "s", thr=steps(T.RESTORABLE_LAG_S / 2, T.RESTORABLE_LAG_S),
           desc="Data loss on a point-in-time restore is at most 5 minutes (D2).")
    d.bars("backup: age of the last successful backup by store, s", f'time() - max by (store) (backup_last_success_timestamp_seconds{{{F}}})', "{{store}}", "s",
           desc="BackupMissing pages when the age exceeds twice the backup interval of the store.")
    d.row("Restore speed")
    d.ts("restore: duration against its target by store, s", [(f'max by (store) (backup_restore_duration_seconds{{{F}}})', "{{store}} duration"),
                                                              (f'max by (store) (backup_restore_target_seconds{{{F}}})', "{{store}} target")], "s",
         desc="Alerts fire at 80% of the target; the Aurora target is 30 minutes (D4).")
    d.ts("restore: duration, % of the target by store", [("100 * " + ratio(f'max by (store) (backup_restore_duration_seconds{{{F}}})', f'max by (store) (backup_restore_target_seconds{{{F}}})'),
                                                          "{{store}}")], "percent", hi=150, thr=steps(T.RESTORE_TARGET_FRACTION * 100))
    size = [{"matcher": {"id": "byRegexp", "options": ".* size"}, "properties": [{"id": "unit", "value": "bytes"}, {"id": "custom.axisPlacement", "value": "right"}]}]
    d.ts("restore: duration against the data size", [(f'max by (store) (backup_restore_duration_seconds{{{F}}})', "{{store}} duration"),
                                                     (f'max by (store) (backup_source_size_bytes{{{F}}})', "{{store}} size")], "s", overrides=size,
         desc="Duration on the left axis, data size on the right: the restore time against data growth.")
    d.table("restore test: last result by store", f'min by (store) (restore_test_success{{{F}}})', w=12, value_name="Result", thr=steps(None, 1, invert=True),
            mappings=[{"type": "value", "options": {"0": {"text": "failed", "color": "red", "index": 0}, "1": {"text": "passed", "color": "green", "index": 1}}}],
            desc="Result of the last daily restore and its data check.")
    d.row("Copies")
    d.ts("snapshot copies: age of the last copy by region, s", [(top(f'time() - max by (store, region) (snapshot_copy_last_success_timestamp_seconds{{{F}}})'), "{{store}} {{region}}")], "s",
         thr=steps(T.SNAPSHOT_COPY_STALE_S), desc="SnapshotCopyStale warns above 2 hours.")
    d.ts("backup: copy job failures per 24 h by vault", [(f'sum by (backup_vault) (increase(aws_backup_number_of_copy_jobs_failed_sum{{{F}}}[1d]))', "{{backup_vault}}")], "short", thr=steps(1))
    out.append(("l3-data", d))

    d = Dashboard("dr-switch", TITLES["dr-switch"], "l3", ["dr", "switch"], links=nav("platform-overview", "backup", "data-stores"), runbooks=["backup-dr", "network", "meta"],
                  description="Recovery regions us-east-1 and us-east-2: replication, probes, test history.")
    probe = f'min by (probe_point) (probe_success{{env=~"$env",probe_target="region-health"}})'
    d.row("Overview")
    d.stat("aurora global: worst lag", f'max(aws_rds_aurora_global_db_replication_lag_maximum{{{F}}})', "ms", thr=steps(T.AURORA_GLOBAL_LAG_MS / 2, T.AURORA_GLOBAL_LAG_MS), decimals=0,
           desc="Pages above 5 s; the RPO budget is 10 s (D7).")
    d.stat("probes: points failing", f"count({probe} == 0) or vector(0)", "short", thr=steps(1, 2), desc="RegionDown pages when two of the three independent points fail.")
    d.stat("dr test: days since last switch", f'(time() - max(dr_switch_test_last_success_timestamp_seconds{{env=~"$env"}})) / 86400', "suffix: days", thr=steps(T.DR_TEST_OVERDUE_D),
           decimals=0, desc="The test is quarterly, to us-east-1 and us-east-2 in turn; DrSwitchTestOverdue warns after 100 days.")
    d.stat("dr test: last switch duration", f'max(dr_switch_test_duration_seconds{{env=~"$env"}}) / 60', "suffix: min", thr=steps(60, 75), decimals=0, desc="RTO target 60 minutes, 75 in plan B.")
    d.stat("dr: lowest cache warm ratio", f'100 * min(cache_warm_ratio{{{F}}})', "percent", hi=100, thr=steps(T.CACHE_WARM_RATIO * 100, invert=True),
           desc="A cell takes traffic at 75% of the priority keys.")
    d.row("Replication")
    d.ts("aurora global: replication lag by region, ms", [(f'max by (global_cluster, region) (aws_rds_aurora_global_db_replication_lag_maximum{{{F}}})', "{{global_cluster}} {{region}}")], "ms",
         thr=steps(T.AURORA_GLOBAL_LAG_MS / 2, T.AURORA_GLOBAL_LAG_MS) + [{"color": "red", "value": T.AURORA_RPO_BUDGET_MS}], desc="Pages above 5 s; the RPO budget is 10 s (D7).")
    d.ts("dynamodb global tables: replication latency (top 8), ms", [(top(f'max by (table_name, receiving_region) (aws_dynamodb_replication_latency_maximum{{{F}}})'),
                                                                      "{{table_name}} {{receiving_region}}")], "ms", thr=steps(T.DYNAMODB_GLOBAL_LAG_MS))
    d.ts("s3: replication latency (top 8 buckets), s", [(top(f'max by (bucket, destination_region) (aws_s3_replication_latency_maximum{{{F}}})'), "{{bucket}} {{destination_region}}")], "s",
         thr=steps(T.S3_REPLICATION_S), desc="Replication Time Control target is 15 minutes.")
    d.ts("snapshot copies: age by region, s", [(top(f'time() - max by (store, region) (snapshot_copy_last_success_timestamp_seconds{{{F}}})'), "{{store}} {{region}}")], "s",
         thr=steps(T.SNAPSHOT_COPY_STALE_S), link=to("backup"))
    d.row("Detection")
    d.ts("probes: region health by probe point, 1 = healthy", [(probe, "{{probe_point}}")], "short", hi=1, thr=steps(None, 1, invert=True),
         desc="The switch is proposed when two of three independent points fail.")
    d.ts("synthetic payment: success by probe point, 1 = success", [(f'min by (probe_point) (synthetic_payment_success{{env=~"$env"}})', "{{probe_point}}")], "short", hi=1,
         thr=steps(None, 1, invert=True), desc="SyntheticPaymentFailing pages when two points fail.")
    out.append(("l3-data", d))

    d = Dashboard("edge", TITLES["edge"], "l3", ["edge", "security"], links=nav("platform-overview", "kubernetes"), runbooks=["network", "security-pci"], description="What happens at the entrance?")
    cert_days = '(min by (target) (probe_ssl_earliest_cert_expiry{env=~"$env"}) - time()) / 86400'
    d.row("Overview")
    d.stat("edge: certs expiring in 14 days", f"count({cert_days} < {T.CERT_EXPIRY_CRIT_D}) or vector(0)", "short", thr=steps(None, 1),
           desc="CertificateExpiryCritical pages below 14 days.")
    d.stat("security: events, last hour", 'sum(increase(security_events_total{env=~"$env"}[1h])) or vector(0)', "short", thr=steps(None, 1),
           desc="Root login, break-glass, SCP or IAM change outside Terraform; each one pages security.")
    d.stat("security: PAN detections, 24 h", 'sum(increase(pan_detected_total{env=~"$env"}[1d])) or vector(0)', "short", thr=steps(None, 1), desc="Card numbers found in logs; any hit pages security.")
    d.row("Traffic")
    d.ts("router: rate-limited responses (429) by cell, reqps", [(f'sum by (cell) (rate(http_server_requests_total{{{FC},service="router",code="429"}}[5m]))', "{{cell}}")], "reqps",
         link=to("router", "cell"))
    d.ts("waf: blocked requests by web ACL, reqps", [(f'sum by (web_acl) (rate(aws_wafv2_blocked_requests_sum{{{F}}}[5m]))', "{{web_acl}}")], "reqps", thr=steps(T.WAF_BLOCKED_RPS))
    d.row("Network")
    d.ts("egress: NAT port allocation errors per second", [(f'sum by (nat_gateway_id) (rate(aws_natgateway_error_port_allocation_sum{{{F}}}[5m]))', "{{nat_gateway_id}}")], "ops",
         thr=steps(None, 0.001), desc="Any error pages: outbound PSP calls fail.")
    d.ts("egress: firewall dropped packets by firewall, pps", [(f'sum by (firewall) (rate(aws_networkfirewall_dropped_packets_sum{{{F}}}[5m]))', "{{firewall}}")], "pps", thr=steps(T.FIREWALL_DROPS_PPS))
    d.ts("edge: certificate days left (soonest 8)", [(bottom(cert_days), "{{target}}")], "suffix: days", thr=steps(30, T.CERT_EXPIRY_CRIT_D, invert=True))
    d.ts("edge: CloudFront 5xx share by distribution, %", [(f'max by (distribution) (aws_cloudfront_5xx_error_rate_average{{{F}}})', "{{distribution}}")], "percent", hi=100,
         thr=steps(T.CLOUDFRONT_5XX_PCT))
    d.row("Security")
    d.ts("security: events per hour by kind", [('sum by (event) (increase(security_events_total{env=~"$env"}[1h]))', "{{event}}")], "short")
    d.ts("guardduty: findings per hour by severity", [('sum by (severity) (increase(guardduty_findings_total{env=~"$env"}[1h]))', "{{severity}}")], "short")
    out.append(("l3-edge", d))

    d = Dashboard("cost", TITLES["cost"], "finops", ["cost"], links=nav("platform-overview", "cells"), description="How much do 1000 payments cost?")
    d.row("Unit cost")
    d.stat("finops: cost per 1000 payments", ratio('sum(finops_cost_usd_per_day{env=~"$env"})', '(sum(increase(payment_attempts_total{env=~"$env"}[1d])) / 1000)'), "currencyUSD", decimals=3,
           desc="Daily spend divided by the payment attempts of the last 24 hours, per 1000.")
    d.stat("finops: spend this month", 'sum(finops_cost_usd_month_to_date{env=~"$env"})', "currencyUSD", decimals=0)
    d.stat("finops: budget used", "100 * " + ratio('sum(finops_cost_usd_month_to_date{env=~"$env"})', 'sum(finops_budget_usd_month{env=~"$env"})'), "percent", hi=120, thr=steps(80, 100),
           desc="Month-to-date spend against the monthly budget.")
    d.row("Spend")
    d.bars("finops: last daily spend by component, USD", 'sum by (component) (finops_cost_usd_per_day{env=~"$env"})', "{{component}}", "currencyUSD")
    d.ts("finops: daily spend by component over time, USD", [('sum by (component) (finops_cost_usd_per_day{env=~"$env"})', "{{component}}")], "currencyUSD")
    d.ts("finops: spot interruptions per hour", [('sum(increase(karpenter_interruption_received_messages_total{env=~"$env"}[1h]))', "interruptions")], "short")
    out.append(("finops", d))
    return out
