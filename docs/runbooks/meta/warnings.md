# meta: non-paging alerts

Each section is the runbook of one ticket or Slack alert; the alert annotation links to its anchor. A ticket is handled in working hours; if the condition persists past the stated escalation, the owner raises it to the on-call.

## watchdog

Alert `Watchdog`, severity none, owner observability-oncall, dashboard https://grafana.payments.internal/d/platform-overview.

### Symptom

Watchdog fires all the time and is sent to an external dead man's switch every minute; no human sees it while the pipeline works. If the external service stops receiving it, it pages the on-call.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=Watchdog`) runs the read-only step of SSM document `pay-runbook-watchdog`.
2. Check Prometheus rule evaluation and the Alertmanager pods.
3. Check the receiver `deadmans-switch` delivery in the Alertmanager notification metrics.

### Actions

1. Restore Prometheus or Alertmanager through ArgoCD (document step `restart-alert-pipeline`).
2. Confirm the heartbeat arrives again at the external service.

### Escalation

The external service pages the platform primary; escalate to the commander if alerts are lost for more than 15 minutes.

### SSM document

`pay-runbook-watchdog`

## prometheus-rule-evaluation-failing

Alert `PrometheusRuleEvaluationFailing`, severity warning, owner observability-oncall, dashboard https://grafana.payments.internal/d/platform-overview.

### Symptom

Rules of a group fail to evaluate.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=PrometheusRuleEvaluationFailing`) runs the read-only step of SSM document `pay-runbook-prometheus-rule-evaluation-failing`.
2. Read the Prometheus log for the failing rule and the error (usually a bad query or a missing series).

### Actions

1. Fix the rule through a pull request; pint should have caught it.

### Escalation

Ticket to observability.

### SSM document

`pay-runbook-prometheus-rule-evaluation-failing`

## active-series-budget-exceeded

Alert `ActiveSeriesBudgetExceeded`, severity warning, owner observability-oncall, dashboard https://grafana.payments.internal/d/platform-overview.

### Symptom

The number of active series in a region passed 2 million.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=ActiveSeriesBudgetExceeded`) runs the read-only step of SSM document `pay-runbook-active-series-budget-exceeded`.
2. Run the top-metrics-by-growth report and find the label that grew.

### Actions

1. Drop or relabel the label in the exporter config; `payment_id`, `customer_id`, tokens and card data are never allowed in labels.

### Escalation

Ticket to observability.

### SSM document

`pay-runbook-active-series-budget-exceeded`
