---
id: 002-central-logs
status: draft
spec: specs/001-devops-platform
---

# Addendum 002-central-logs: one central OpenSearch for the logs, through Logstash

The owner replaced Loki and the per-environment OpenSearch domains with one central OpenSearch domain in shared-services. The OpenTelemetry collector on every node sends the logs to Logstash, which masks them again and writes them with AWS IAM. Audit logs reach the domain through OpenSearch Ingestion from the log archive. The page is `docs/architecture/runtime/logging.md`.

## Changed

| ID | Requirement | Verification | Implementation | Source |
|---|---|---|---|---|
| FR-INF-24 | Analytics (MSK, ClickHouse) shall run outside the CDE on its own cluster in the working region; the log search runs on the central OpenSearch domain of shared-services. | inspection | `infra/live/<env>/eu-central-1/analytics/{eks,karpenter,msk,clickhouse}`; `infra/live/shared-services/eu-central-1/logs/`. | Section 2, ADR-011, owner decision on central logs |
| FR-OBS-1 | Metrics, logs and traces shall be collected by an OpenTelemetry collector on every node and stored in VictoriaMetrics, the central OpenSearch domain (through Logstash) and Tempo, with errors in Sentry. | test | `observability/otel/collector.yaml` with `observability/otel/tests`; `deploy/platform/otel-collector`; `deploy/platform/logstash` with its chart tests; `infra/modules/opensearch`, `infra/modules/opensearch-indices`. | Section 7, owner decision on central logs |
