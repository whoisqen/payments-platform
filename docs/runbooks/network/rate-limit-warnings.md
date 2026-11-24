# network: rate limit and load shedding warnings

Each section is the runbook of one ticket or Slack alert; the alert annotation links to its anchor. A ticket is handled in working hours; if the condition persists past the stated escalation, the owner raises it to the on-call.

## rate-limit-hits-merchant

Alert `RateLimitHitsMerchant`, severity warning, owner platform-oncall, dashboard https://grafana.payments.internal/d/edge.

### Symptom

The edge returns 429 with `Retry-After` to one merchant (`merchant_id` label of the alert) for 10 minutes.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=RateLimitHitsMerchant`) runs the read-only step of SSM document `pay-runbook-rate-limit-hits-merchant`.
2. Check the limited requests of the merchant against its limit in the tenant file in Git.
3. Check whether the merchant retries in a loop (same rate of limited and total hits) or has a planned sale.

### Actions

1. For a planned or legitimate peak, raise the merchant override in its tenant file in Git and merge it; the rate limit service reloads it.
2. For a retry loop, contact the merchant; do not raise the limit.
3. Check `MerchantShareOfCellHigh` before raising: a merchant above 30% of a cell needs a split, not a larger limit.

### Escalation

Ticket to platform; raise to the on-call if other merchants of the cell see 429 or 5xx.

### SSM document

`pay-runbook-rate-limit-hits-merchant`

## merchant-share-of-cell-high

Alert `MerchantShareOfCellHigh`, severity warning, owner platform-oncall, dashboard https://grafana.payments.internal/d/edge.

### Symptom

One merchant sends more than 30% of the rate-limited descriptors of a cell for 5 minutes; the cell headroom is 40%.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=MerchantShareOfCellHigh`) runs the read-only step of SSM document `pay-runbook-merchant-share-of-cell-high`.
2. Check the share and the cell load on the edge dashboard and whether the `hot-merchant` controller added a second cell for new payments (it acts above 40% of the capacity).
3. Check the 5xx rate of the other merchants of the cell.

### Actions

1. Confirm that the controller reacted; if not, the controller is the incident: raise it to payments-core.
2. Keep the merchant limit in place while the controller reacts (1-2 minutes); raise it only after the second cell serves new payments.

### Escalation

Ticket to platform; raise to the on-call when the share stays above 30% for 30 minutes or other merchants are affected.

### SSM document

`pay-runbook-merchant-share-of-cell-high`

## load-shedding-reads-active

Alert `LoadSheddingReadsActive`, severity warning, owner platform-oncall, dashboard https://grafana.payments.internal/d/edge.

### Symptom

The edge returns 429 for lists, reports or status polling; payments are still served.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=LoadSheddingReadsActive`) runs the read-only step of SSM document `pay-runbook-load-shedding-reads-active`.
2. Check the requests per class and the top-5 merchants on the edge dashboard; status polling above 1 per second from one merchant is a client problem.
3. Compare gateway pod count and CPU with the HPA maximum.

### Actions

1. Scale the gateway if the load is general (document step `scale-gateway`).
2. For one polling merchant, ask it to use webhooks instead of polling.

### Escalation

Ticket to platform; `LoadSheddingActive` pages if payments are shed next.

### SSM document

`pay-runbook-load-shedding-reads-active`

## rate-limit-service-down

Alert `RateLimitServiceDown`, severity warning, owner platform-oncall, dashboard https://grafana.payments.internal/d/edge.

### Symptom

No rate limit service pod of a cell is up. The edge fails open: payments flow, but there is no per-merchant protection in that cell.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=RateLimitServiceDown`) runs the read-only step of SSM document `pay-runbook-rate-limit-service-down`.
2. Confirm fail-open: `envoy_http_ratelimit_failure_mode_allowed` grows and the gateway returns no 5xx.
3. Check the pods and the Redis (MemoryDB) backend of the service.

### Actions

1. Restore the service pods or the Redis backend (document step `restart-ratelimit`).
2. Do not set the filter to fail-closed: payments would fail with the service.
3. While it is down, watch `MerchantShareOfCellHigh`; the local gateway limit still protects the pods.

### Escalation

Ticket to platform; raise to the on-call after 30 minutes or when one merchant exceeds 30% of a cell.

### SSM document

`pay-runbook-rate-limit-service-down`

## rate-limit-service-errors

Alert `RateLimitServiceErrors`, severity warning, owner platform-oncall, dashboard https://grafana.payments.internal/d/edge.

### Symptom

Calls to the rate limit service fail or time out and the gateway lets those requests pass (fail-open).

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=RateLimitServiceErrors`) runs the read-only step of SSM document `pay-runbook-rate-limit-service-errors`.
2. Compare `ratelimit_service_call_should_rate_limit_error` with `envoy_http_ratelimit_failure_mode_allowed`: both growing confirm fail-open.
3. Check Redis latency, service CPU and the call timeout.

### Actions

1. Scale the service or fix the Redis backend (document step `restart-ratelimit`).
2. Leave fail-open on; payments take priority over per-merchant limits.

### Escalation

Ticket to platform; raise to the on-call after 30 minutes.

### SSM document

`pay-runbook-rate-limit-service-errors`
