from common import a, gap
from common import rule_labels, annotations

L = "meta"
O = "observability"

al = dict(layer=L, group="pipeline", name="Watchdog", sev="none", team=O, svc="alertmanager", comp="watchdog", dash="platform-overview",
          expr="vector(1)", f="0m", sum="Watchdog: always firing; silence of this alert means the alert pipeline is broken",
          series=[("vector", "0", "0")], labels={}, skip_auto=True,
          failure="alert pipeline silent (dead man's switch)", impact="alerts may not reach anyone; an external service pages when the heartbeat stops",
          sym="Watchdog fires all the time and is sent to an external dead man's switch every minute; no human sees it while the pipeline works. If the external service stops receiving it, it pages the on-call.",
          diag=["Check Prometheus rule evaluation and the Alertmanager pods.", "Check the receiver `deadmans-switch` delivery in the Alertmanager notification metrics."],
          act=["Restore Prometheus or Alertmanager through ArgoCD (document step `restart-alert-pipeline`).", "Confirm the heartbeat arrives again at the external service."],
          esc="The external service pages the platform primary; escalate to the commander if alerts are lost for more than 15 minutes.")
a(**al)
w = [x for x in __import__("common").ALL if x["name"] == "Watchdog"][0]
w["extra_tests"] = [{"interval": "1m", "input_series": [], "alert_rule_test": [{"eval_time": "5m", "alertname": "Watchdog", "exp_alerts": [{"exp_labels": rule_labels(w), "exp_annotations": annotations(w)}]}]}]

a(layer=L, group="pipeline", name="AlertmanagerNotificationsFailing", sev="critical", team=O, svc="alertmanager", comp="alertmanager", dash="platform-overview",
  expr="sum by (integration) (rate(alertmanager_notifications_failed_total[5m])) > 0", f="5m",
  sum="Alertmanager cannot deliver notifications",
  series=[('alertmanager_notifications_failed_total{integration="pagerduty"}', "0+2x{n}", "0+0x{n}")], labels={"integration": "pagerduty"},
  failure="notification delivery failing", impact="pages or Slack messages are lost",
  sym="Alertmanager fails to send notifications to an integration.",
  diag=["Read the Alertmanager log for the receiver and the HTTP error.", "Check the secret files of the receiver and the status page of the provider."],
  act=["Fix the credential or the network path; verify with a test alert from the on-call tool.", "Use the phone bridge of the incident commander while the integration is down."],
  esc="Page the commander through the secondary channel: the failing integration cannot carry this alert.")

a(layer=L, group="pipeline", name="PrometheusRuleEvaluationFailing", sev="warning", team=O, svc="prometheus", comp="prometheus", dash="platform-overview",
  expr="sum by (rule_group) (increase(prometheus_rule_evaluation_failures_total[10m])) > 0", f="5m",
  sum="A rule group fails to evaluate",
  series=[('prometheus_rule_evaluation_failures_total{rule_group="application-psp"}', "0+1x{n}", "0+0x{n}")], labels={"rule_group": "application-psp"},
  failure="rule evaluation failing", impact="alerts of the group do not fire",
  sym="Rules of a group fail to evaluate.",
  diag=["Read the Prometheus log for the failing rule and the error (usually a bad query or a missing series)."],
  act=["Fix the rule through a pull request; pint should have caught it."],
  esc="Ticket to observability.")

a(layer=L, group="pipeline", name="ActiveSeriesBudgetExceeded", sev="warning", team=O, svc="prometheus", comp="cardinality", dash="platform-overview",
  expr="sum by (region) (prometheus_tsdb_head_series) > 2000000", f="15m",
  sum="Active series exceed the budget of 2 million per region",
  series=[('prometheus_tsdb_head_series{region="eu-central-1"}', "2500000x{n}", "900000x{n}")],
  failure="cardinality budget exceeded", impact="cost and query slowness; a label with unbounded values is the usual cause",
  sym="The number of active series in a region passed 2 million.",
  diag=["Run the top-metrics-by-growth report and find the label that grew."],
  act=["Drop or relabel the label in the exporter config; `payment_id`, `customer_id`, tokens and card data are never allowed in labels."],
  esc="Ticket to observability.")

gap(L, "alloy-not-forwarding", "alloy", "Alloy stops forwarding telemetry to the central stack", "metrics, logs and traces of a cluster go missing", "critical", "needs the Alloy self-metrics in the metrics catalog")
