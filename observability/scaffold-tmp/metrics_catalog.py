import json
import re
import sys
from pathlib import Path

sys.path.insert(0, "/data/vlad/portfolio/payments-platform/.claude/worktrees/agent-a1894cfe0c95fc100/observability/coverage")
import alert_coverage as cov  # noqa: E402

OBS = Path("/data/vlad/portfolio/payments-platform/.claude/worktrees/agent-a1894cfe0c95fc100/observability")
SOURCES = [
    (r"^(up|ALERTS)$", "prometheus"),
    (r"^synthetic_", "synthetic-probe"),
    (r"^(http_server_|platform_overhead_|psp_|payment_|payments_|drain_lag|drainer_|scheduler_|webhook_|retry_|dependency_|circuit_breaker|dlq_|reconciliation_|cache_warm|kms_request)", "app-otel-sdk"),
    (r"^node_os_image_age", "node-image-exporter"),
    (r"^node_", "node-exporter"),
    (r"^(container_)", "cadvisor"),
    (r"^kube_", "kube-state-metrics"),
    (r"^karpenter_", "karpenter"),
    (r"^subnet_", "subnet-exporter"),
    (r"^pg_", "postgres-exporter"),
    (r"^redis_", "redis-exporter"),
    (r"^kafka_", "kafka-exporter"),
    (r"^ClickHouse", "clickhouse"),
    (r"^aws_", "yace"),
    (r"^probe_", "blackbox-exporter"),
    (r"^vault_", "vault"),
    (r"^(guardduty_|security_events_)", "security-events-exporter"),
    (r"^kyverno_", "kyverno"),
    (r"^kms_key", "kms-exporter"),
    (r"^certmanager_", "cert-manager"),
    (r"^(backup_|restore_|database_latest|snapshot_copy|dr_switch)", "backup-exporter"),
    (r"^memorydb_", "memorydb-event-exporter"),
    (r"^pan_detected", "otel-collector"),
    (r"^finops_", "cost-exporter"),
    (r"^argocd_", "argocd"),
    (r"^(alertmanager_|prometheus_)", "prometheus"),
]


def source(name):
    for pattern, src in SOURCES:
        if re.match(pattern, name):
            return src
    raise SystemExit(f"no source for {name}")


alerts, recorded = cov.load_rules([OBS / "alerts", OBS / "slo" / "generated"])
metrics = set()
for rule in alerts.values():
    metrics |= cov.extract_metrics(rule["expr"])
for path in (OBS / "dashboards").rglob("*.json"):
    doc = json.loads(path.read_text())
    for p in doc["panels"]:
        for t in p.get("targets", []):
            metrics |= cov.extract_metrics(t["expr"])
    for a in doc["annotations"]["list"]:
        metrics |= cov.extract_metrics(a["expr"])
for rec in ("up",):
    metrics.add(rec)
metrics -= recorded
out = {"note": "Exported metrics by source; reconcile with the live stage Prometheus in CI (pint). A metric missing here makes an alert uncovered.", "metrics": {m: source(m) for m in sorted(metrics)}}
(OBS / "coverage" / "metrics-catalog.json").write_text(json.dumps(out, indent=2) + "\n")
print(len(metrics), "metrics")
