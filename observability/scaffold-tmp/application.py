from common import a, gap, EXTRA_MODES, ALL

L = "application"
T = "payments-core"

a(layer=L, group="psp", name="PSPDegraded", sev="critical", team=T, svc="router", comp="psp", dash="payments",
  expr='sum by (psp) (rate(psp_requests_total{outcome="technical_error"}[5m])) / sum by (psp) (rate(psp_requests_total[5m])) > 0.05', f="5m",
  sum="PSP technical errors exceed 5% of its calls",
  series=[('psp_requests_total{psp="acme",outcome="technical_error"}', "0+30x{n}", "0+1x{n}"), ('psp_requests_total{psp="acme",outcome="authorized"}', "0+100x{n}", "0+100x{n}")],
  labels={"psp": "acme"},
  failure="PSP degraded", impact="authorization rate falls; routing must move traffic to another PSP; inhibits the authorization-rate alert of this PSP",
  sym="More than 5% of the calls to one PSP end in technical errors (timeouts, 5xx, connection failures) for 5 minutes.",
  diag=["Check the PSP status page and the latency heatmap on the payments dashboard.", "Check the circuit breaker state of the PSP and the routing weights.", "Check whether the errors are limited to one cell or one payment method."],
  act=["Shift routing away from the PSP with document step `route-away-psp` (changes the routing weight through the control plane, audited).", "Do not retry charges against the same PSP; timeouts become the unknown state and sync resolves them.", "Re-enable the PSP in steps of 10% after its error rate stays under 1% for 15 minutes."],
  esc="Open the PSP incident channel; payments-core lead is informed when the PSP carries more than 30% of the volume.")

a(layer=L, group="psp", name="PspLatencyP99High", sev="warning", team=T, svc="router", comp="psp", dash="payments",
  expr="histogram_quantile(0.99, sum by (psp, le) (rate(psp_request_duration_seconds_bucket[5m]))) > 3", f="5m",
  sum="PSP p99 latency above 3 seconds",
  series=[('psp_request_duration_seconds_bucket{psp="acme",le="3"}', "0+0x{n}", "0+100x{n}"), ('psp_request_duration_seconds_bucket{psp="acme",le="10"}', "0+100x{n}", "0+100x{n}"), ('psp_request_duration_seconds_bucket{psp="acme",le="+Inf"}', "0+100x{n}", "0+100x{n}")],
  labels={"psp": "acme"},
  failure="PSP slow", impact="long waits for merchants and more unknown-state payments at the 15 s timeout",
  sym="The p99 of the PSP call duration is above 3 seconds.",
  diag=["Compare with the PSP profile timeout and the share of timeouts."],
  act=["Lower the routing weight of the PSP if the share of timeouts grows."],
  esc="Ticket to payments-core; the PSP degraded alert pages if errors follow.")

a(layer=L, group="psp", name="PspCircuitBreakerOpen", sev="warning", team=T, svc="router", comp="psp", dash="payments",
  expr='max by (psp) (circuit_breaker_state{dependency="psp-authorize"}) == 2', f="2m",
  sum="The circuit breaker of a PSP is open",
  series=[('circuit_breaker_state{dependency="psp-authorize",psp="acme"}', "2x{n}", "0x{n}")],
  labels={"psp": "acme"},
  failure="PSP circuit breaker open", impact="the PSP receives no traffic; fast failure or reroute",
  sym="The router opened the breaker of a PSP (state 2).",
  diag=["Read the breaker trip reason and the half-open probe results on the router dashboard."],
  act=["No manual action if the half-open probe recovers; otherwise follow `psp-degraded`."],
  esc="Ticket to payments-core.")

a(layer=L, group="psp", name="AuthorizationRateDrop", sev="warning", team=T, svc="router", comp="authorization", dash="payments",
  expr='sum by (psp) (rate(payment_attempts_total{outcome="authorized"}[15m])) / sum by (psp) (rate(payment_attempts_total[15m])) < (sum by (psp) (rate(payment_attempts_total{outcome="authorized"}[15m] offset 1w)) / sum by (psp) (rate(payment_attempts_total[15m] offset 1w))) - 0.05', f="15m",
  sum="Authorization rate is 5 points lower than the same time a week ago",
  series=[('payment_attempts_total{psp="acme",outcome="authorized"}', "0", "0"), ('payment_attempts_total{psp="acme"}', "0", "0")],
  labels={"psp": "acme"}, skip_auto=True,
  extra_tests=[
      {"interval": "5m", "input_series": [{"series": 'payment_attempts_total{psp="acme",outcome="authorized"}', "values": "0+95x2016 191520+70x200"}, {"series": 'payment_attempts_total{psp="acme"}', "values": "0+100x2200"}],
       "alert_rule_test": [{"eval_time": "10200m", "alertname": "AuthorizationRateDrop", "exp_alerts": [{"exp_labels": {"severity": "warning", "team": T, "service": "router", "owner": f"{T}-oncall", "layer": L, "failure_mode": "application-authorization-rate-drop", "psp": "acme"}, "exp_annotations": {"summary": "Authorization rate is 5 points lower than the same time a week ago", "runbook_url": "https://github.com/whoisqen/payments-platform/blob/main/docs/runbooks/application/warnings.md#authorization-rate-drop", "dashboard_url": "https://grafana.payments.internal/d/payments"}}]}]},
      {"interval": "5m", "input_series": [{"series": 'payment_attempts_total{psp="acme",outcome="authorized"}', "values": "0+95x2200"}, {"series": 'payment_attempts_total{psp="acme"}', "values": "0+100x2200"}],
       "alert_rule_test": [{"eval_time": "10200m", "alertname": "AuthorizationRateDrop", "exp_alerts": []}]}],
  failure="authorization rate drop against last week", impact="often the first sign of a PSP problem before 5xx appear",
  sym="The authorization rate of a PSP is at least 5 percentage points below the same hour one week ago.",
  diag=["Split the drop by payment method, card country and issuer on the payments dashboard.", "Check whether a routing or fraud rule changed in the last deploy."],
  act=["If one PSP is affected, follow `psp-degraded`.", "If a routing change caused it, roll it back through the control plane."],
  esc="Ticket to payments-core; it becomes a page through the PSP alert or the SLO burn.")

a(layer=L, group="payments", name="UnknownStatePaymentsStale", sev="warning", team=T, svc="scheduler", comp="sync", dash="scheduler",
  expr="sum(payments_unknown_state_stale) > 0", f="10m",
  sum="Payments stay in the unknown state for more than 15 minutes",
  series=[('payments_unknown_state_stale{cell="cell-1"}', "12x{n}", "0x{n}")], labels={},
  failure="unknown state not resolved by sync", impact="merchants see unresolved payments; a charge may exist at the PSP",
  sym="At least one payment has been in the unknown state for over 15 minutes, so sync did not resolve it.",
  diag=["Check the scheduler sync queue and the PSP status endpoint errors."],
  act=["Run a manual sync of the stale payments by reference id with document step `sync-stale` (read-only toward the PSP).", "Never create a second charge for them."],
  esc="Ticket to payments-core; page if the count grows above 100.")

a(layer=L, group="payments", name="SyntheticPaymentFailing", sev="critical", team=T, svc="router", comp="synthetic", dash="payments",
  expr="count(synthetic_payment_success == 0) >= 2", f="3m",
  sum="Synthetic payment fails from at least two of three probe points",
  series=[('synthetic_payment_success{probe_point="use1"}', "0x{n}", "1x{n}"), ('synthetic_payment_success{probe_point="use2"}', "0x{n}", "1x{n}"), ('synthetic_payment_success{probe_point="ext"}', "0x{n}", "1x{n}")], labels={},
  failure="end-to-end payment fails", impact="merchants cannot complete a payment; covers paths that component alerts miss",
  sym="The synthetic payment against the test PSP, sent every 60 seconds, failed from two of three probe points for 3 minutes.",
  diag=["Read the failing step in the probe result: create, confirm or retrieve.", "Check the router 5xx rate and the test PSP status.", "Compare with `region-down`."],
  act=["Follow the alert of the failing component.", "If the test PSP is the only failure, check its connector; it does not affect real merchants."],
  esc="Escalate to the commander if the real authorization rate also drops.")

a(layer=L, group="components", name="Router5xxRateHigh", sev="warning", team=T, svc="router", comp="router", dash="router",
  expr='sum by (cell) (rate(http_server_requests_total{service="router",code=~"5.."}[5m])) / sum by (cell) (rate(http_server_requests_total{service="router"}[5m])) > 0.01', f="5m",
  sum="Router 5xx rate above 1% in a cell",
  series=[('http_server_requests_total{service="router",code="500",cell="cell-1"}', "0+30x{n}", "0+0x{n}"), ('http_server_requests_total{service="router",code="200",cell="cell-1"}', "0+100x{n}", "0+100x{n}")],
  labels={"cell": "cell-1"},
  failure="router errors", impact="failed requests; the SLO burn alerts page when it burns the budget",
  sym="More than 1% of the responses of a cell are 5xx.",
  diag=["Split the errors by route and error source on the router dashboard.", "Check the last rollout of the cell."],
  act=["Roll back the cell if the errors started with a rollout.", "Close the cell with document step `close-cell` only on the commander's order."],
  esc="Ticket to payments-core; the SLO burn alert is the page.")

a(layer=L, group="components", name="LockerErrorRateHigh", sev="critical", team=T, svc="locker", comp="locker", dash="locker",
  expr='sum(rate(http_server_requests_total{service="locker",code=~"5.."}[5m])) / sum(rate(http_server_requests_total{service="locker"}[5m])) > 0.01', f="5m",
  sum="Locker 5xx rate above 1%",
  series=[('http_server_requests_total{service="locker",code="500"}', "0+10x{n}", "0+0x{n}"), ('http_server_requests_total{service="locker",code="200"}', "0+100x{n}", "0+100x{n}")], labels={},
  failure="locker errors", impact="tokenization and card reads fail; every payment with a stored card fails; the locker is in the CDE",
  sym="More than 1% of the locker responses are 5xx.",
  diag=["Check locker pods, KMS errors and Aurora connectivity of the locker database.", "Check the router-to-locker retry budget on the locker dashboard."],
  act=["If KMS throttles, follow the KMS runbook of the security team.", "Scale the locker out through the HPA step `scale-locker` if CPU bound.", "Do not log request bodies while debugging: the locker handles PAN."],
  esc="Page the security on-call too if the errors are authorization or certificate related (CDE component).")

a(layer=L, group="components", name="DrainLagHigh", sev="critical", team=T, svc="drainer", comp="drainer", dash="drainer",
  expr="max by (cell) (drain_lag_seconds) > 5", f="5m",
  sum="Drain lag above 5 seconds",
  series=[('drain_lag_seconds{cell="cell-1"}', "20x{n}", "0.5x{n}")],
  failure="drainer behind", impact="write-behind falls behind; the RPO of payment data grows by the lag (D7)",
  sym="The time from the Redis stream write to the row in PostgreSQL is above 5 seconds.",
  diag=["Check the drainer pods and the batch size on the drainer dashboard.", "Check Aurora writer CPU, locks and `AuroraWriterUnavailable`.", "Check the stream length: `redis-stream-backlog`."],
  act=["Scale the drainer consumers with document step `scale-drainer`.", "If the writer is the bottleneck, follow the Aurora runbooks.", "Never trim the stream: it holds undrained payment state."],
  esc="Escalate to the commander when the lag exceeds 60 seconds.")

a(layer=L, group="components", name="RedisStreamBacklog", sev="critical", team=T, svc="drainer", comp="redis-stream", dash="drainer",
  expr="max by (cell, stream) (redis_stream_length) > 50000", f="5m",
  sum="A Redis stream holds more than 50000 entries",
  series=[('redis_stream_length{cell="cell-1",stream="payments-drain"}', "80000x{n}", "100x{n}")],
  failure="stream backlog", impact="MemoryDB memory grows and the undrained state is at risk",
  sym="The stream that feeds the drainer is longer than 50000 entries.",
  diag=["Check `drain-lag-high` and the drainer pods.", "Check MemoryDB memory: `memory-db-memory-critical`."],
  act=["Follow `drain-lag-high` to restore the drain rate.", "Scale MemoryDB out if memory passes 85%."],
  esc="Escalate to the commander if memory passes 85%.")

a(layer=L, group="components", name="SchedulerQueueDelayHigh", sev="critical", team=T, svc="scheduler", comp="scheduler", dash="scheduler",
  expr="max by (cell) (scheduler_queue_oldest_task_age_seconds) > 600", f="5m",
  sum="The oldest scheduler task waits more than 10 minutes",
  series=[('scheduler_queue_oldest_task_age_seconds{cell="cell-1"}', "900x{n}", "5x{n}")],
  failure="scheduler queue delayed", impact="sync of unknown-state payments and outgoing webhooks are late",
  sym="Tasks wait in the scheduler queue for over 10 minutes.",
  diag=["Check the consumer pods and the task kinds in the queue on the scheduler dashboard.", "Check PSP error rates: sync tasks retry on errors."],
  act=["Scale the consumers with document step `scale-scheduler`.", "Move the failing task kind to the DLQ if it blocks the rest."],
  esc="Escalate to payments-core lead when unknown-state payments are older than 15 minutes.")

a(layer=L, group="components", name="DlqNotEmpty", sev="warning", team=T, svc="scheduler", comp="dlq", dash="scheduler",
  expr="sum by (queue) (dlq_depth) > 0", f="15m",
  sum="A dead-letter queue is not empty",
  series=[('dlq_depth{queue="webhooks"}', "4x{n}", "0x{n}")],
  failure="messages in DLQ", impact="events or webhooks that exhausted their retries wait for a person",
  sym="A DLQ holds messages for over 15 minutes.",
  diag=["Read the failure reason of the newest message (sanitized, no card data)."],
  act=["Fix the cause and replay the messages with document step `replay-dlq`; receivers deduplicate by event_id."],
  esc="Ticket to payments-core.")

a(layer=L, group="components", name="WebhookBacklogOld", sev="warning", team=T, svc="scheduler", comp="webhooks", dash="scheduler",
  expr="max by (cell) (webhook_queue_oldest_age_seconds) > 300", f="10m",
  sum="Outgoing webhooks wait more than 5 minutes",
  series=[('webhook_queue_oldest_age_seconds{cell="cell-1"}', "700x{n}", "5x{n}")],
  failure="webhook queue backlog", impact="merchants receive events late; the 60 s delivery SLO burns",
  sym="The oldest outgoing webhook in the queue is over 5 minutes old.",
  diag=["Check whether one merchant endpoint blocks the workers."],
  act=["Throttle the slow merchant endpoint with document step `isolate-endpoint`."],
  esc="Ticket to payments-core; the SLO burn alert is the page.")

a(layer=L, group="components", name="ReconciliationMismatch", sev="warning", team=T, svc="scheduler", comp="reconciliation", dash="payments",
  expr="sum by (psp) (increase(reconciliation_amount_mismatch_total[1d])) > 0", f="10m",
  sum="Daily PSP reconciliation found amount mismatches",
  series=[('reconciliation_amount_mismatch_total{psp="acme"}', "0+1x{n}", "0+0x{n}")],
  failure="reconciliation mismatch", impact="a payment amount differs from the PSP report: possible double charge or missing capture",
  sym="The reconciliation job found payments whose amount differs from the PSP report.",
  diag=["List the mismatched reference ids from the reconciliation report (no card data)."],
  act=["Hand the list to finance operations; refund a double charge through the PSP connector."],
  esc="Ticket to payments-core and finance operations.")

a(layer=L, group="components", name="MigrationJobFailed", sev="warning", team=T, svc="migrations", comp="migrations", dash="payments",
  expr='kube_job_status_failed{job_name=~".*migrat.*"} > 0', f="1m",
  sum="A migration job failed",
  series=[('kube_job_status_failed{job_name="migrate-router-20261120",namespace="payments-cell-1"}', "1x{n}", "0x{n}")],
  failure="migration job failed", impact="the rollout of the new version is blocked; the schema stays on the old version",
  sym="The migration Job of a rollout failed; the rollout does not continue.",
  diag=["Read the Job log and the pre-migration snapshot status."],
  act=["Fix the migration (expand-contract only) and run the Job again; `down.sql` is never applied in prod."],
  esc="Ticket to the migration author; escalate to data-platform if it holds a lock.")

a(layer=L, group="resilience", name="RetryStorm", sev="warning", team=T, svc="resilience", comp="retries", dash="payments", norules=True,
  expr="", f="5m", sum="Retries exceed 10% of the traffic to a dependency",
  series=[('retry_total{dependency="router-locker"}', "0+20x{n}", "0+1x{n}"), ('dependency_requests_total{dependency="router-locker"}', "0+100x{n}", "0+100x{n}")],
  labels={"dependency": "router-locker"},
  failure="retry storm", impact="retries amplify the load on a recovering dependency",
  sym="More than 10% of the requests to a dependency are retries for 5 minutes.",
  diag=["Find the dependency on the resilience panel and the error that triggers the retries."],
  act=["Fix or isolate the failing dependency; do not raise retry limits.", "Check that only the layer closest to the dependency retries."],
  esc="Ticket to payments-core; the chaos scenario `retry-storm` covers this.")

a(layer=L, group="resilience", name="RetryBudgetExhausted", sev="critical", team=T, svc="resilience", comp="retries", dash="payments", norules=True,
  expr="", f="2m", sum="The retry budget of the locker or PSP sync is exhausted",
  series=[('retry_budget_exhausted_total{dependency="router-locker"}', "0+1x{n}", "0+0x{n}")],
  labels={"dependency": "router-locker"},
  failure="retry budget exhausted for locker or PSP sync", impact="new retries are dropped and requests fail fast; the dependency is badly degraded",
  sym="The retry budget (10% of normal traffic) of the locker or of PSP sync is used up.",
  diag=["Check the dependency health: locker errors, PSP sync errors, circuit breaker state.", "Check `retry_total` by dependency for the amplification source."],
  act=["Restore the dependency first; do not raise the budget.", "If the PSP sync budget is exhausted, unknown-state payments stay unresolved: follow `psp-degraded`."],
  esc="Escalate to the commander if the locker is the dependency.")

a(layer=L, group="resilience", name="RetryBudgetExhaustedNonCritical", sev="warning", team=T, svc="resilience", comp="retries", dash="payments", norules=True,
  expr="", f="10m", sum="The retry budget of a dependency is exhausted",
  series=[('retry_budget_exhausted_total{dependency="aurora"}', "0+1x{n}", "0+0x{n}")],
  labels={"dependency": "aurora"},
  failure="retry budget exhausted", impact="requests to that dependency fail fast instead of retrying",
  sym="A dependency other than the locker and PSP sync used up its retry budget.",
  diag=["Check the dependency alerts of the data layer."],
  act=["Fix the dependency; the budget stays at 10%."],
  esc="Ticket to the dependency owner.")

SLO = [("authorization-availability", "PaymentsAuthorizationAvailabilityBurnFast", "authorization availability burns its 99.99% budget", "high error ratio of POST /payments/{id}/confirm"),
       ("platform-overhead-latency", "PaymentsPlatformOverheadLatencyBurnFast", "platform overhead above 150 ms burns its 99.9% budget", "slow platform processing"),
       ("payment-status-read", "PaymentsStatusReadBurnFast", "payment status reads burn their 99.95% budget", "slow or failing GET /payments/{id}"),
       ("merchant-webhook-delivery", "PaymentsWebhookDeliveryBurnFast", "webhook delivery burns its 99.9% budget", "webhooks delivered later than 60 s")]
for slug, alert, what, impact in SLO:
    EXTRA_MODES.append(dict(layer=L, id=f"application-slo-{slug}", component="slo", failure=f"SLO burn: {what}", impact=impact, severity="critical", alert=alert, signal="slo", detect_within="6m"))

gap(L, "new-version-regression", "release", "Error or latency regression right after a new version", "bad release reaches all cells before the SLO burn alert", "warning", "canary analysis alert is owned by the delivery layer and not written yet")
gap(L, "merchant-config-sync", "router", "Merchant configuration cache not refreshed", "routing with stale merchant rules", "warning", "no freshness metric emitted by the router yet")
