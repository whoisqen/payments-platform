---
status: baseline
---

# Observability, scaling and testing requirements

Alerts, monitoring as code, on-call, scaling, load and chaos tests and incident analysis. Thresholds equal `nfr.md`.

## Telemetry

| ID | Requirement | Verification | Implementation | Source |
|---|---|---|---|---|
| FR-OBS-1 | Metrics, logs and traces shall be collected by an OpenTelemetry collector on every node and stored in VictoriaMetrics, Loki and Tempo, with errors in Sentry. | test | `observability/otel/collector.yaml` with `observability/otel/tests`; `deploy/platform/{otel-collector,victoria-metrics,loki,tempo,sentry}`; `tests/contracts/test_telemetry_path.py`. | Section 7 |
| FR-OBS-2 | Metric labels shall come from one allowlist, and active series above 2 million per region shall alert. | test | `observability/standards/labels.yaml`; alert `ActiveSeriesBudgetExceeded` (`prometheus_tsdb_head_series > 2000000`). | Section 7, section 15 |
| FR-OBS-3 | The metrics store, Alertmanager and the collector shall stay available when one replica or node is lost. | test | `tests/contracts/test_platform_ha.py` (two replicas, spread over zones, three-node metrics store with replication 2, Alertmanager cluster of three). | Section 7 |
| FR-OBS-4 | Payment business metrics (authorization rate per PSP, PSP latency and technical errors, unknown-state payments) shall be exported and alerted. | test | Alerts `AuthorizationRateDrop`, `PspLatencyP99High` (p99 above 3 s), `PSPDegraded`, `UnknownStatePaymentsStale` in `observability/alerts/application/`; `observability/coverage/metrics-catalog.json`. | Section 7 (business metrics) |
| FR-OBS-5 | Data-store exporters (PostgreSQL, Redis, Kafka, ClickHouse, blackbox) shall be configured as code. | test | `observability/exporters/*.yaml` with `observability/exporters/tests`; `deploy/platform/exporters`. | Section 15 (exporters) |

## Alerts and monitoring as code

| ID | Requirement | Verification | Implementation | Source |
|---|---|---|---|---|
| FR-OBS-6 | SLO alerts shall be generated as multi-window burn-rate rules from the SLO files, paging on fast burn and opening a ticket on slow burn. | test | `observability/slo/generate.py` over `observability/slo/*.yaml` into `observability/slo/generated`; `observability/slo/tests`. | Section 15 (alerts and SLO as code) |
| FR-OBS-7 | Every alert shall carry `severity`, `team`, `owner`, `layer`, `failure_mode`, `runbook_url` and `dashboard_url`, and reference a metric that is exported. | test | `observability/tests/test_contract.py`; `observability/coverage/alert_coverage.py` against `metrics-catalog.json`. | Section 25.3 |
| FR-OBS-8 | Every alert shall have anti-flap timers suited to its kind and be announced once while it fires. | test | `observability/tests/test_alert_timers.py`; `repeat_interval: 8760h` in `observability/alertmanager/alertmanager.yaml`. | Section 25.5 |
| FR-OBS-9 | Alert coverage per layer shall meet `NFR-COV-1`, and a coverage drop in a pull request shall be reported in CI. | test | `observability/coverage/alert_coverage.py` with `targets.yaml` and `tests/test_coverage.py`; catalog `observability/coverage/catalog/*.yaml`. | Section 25.3, section 25.1 |
| FR-OBS-10 | Recovery alerts shall use the thresholds of `nfr.md`: Aurora lag 5 s and 10 s, latest restorable time 5 min for 10 min, restore at 80% of target, drain lag 5 s, stream length 50,000, warm ratio 0.75. | test | `observability/alerts/backup-dr/{replication,restore}.yaml`, `application/components.yaml`, `data/memorydb.yaml`; unit tests in `observability/tests/`. | D2, D4, D7, D8 |
| FR-OBS-11 | The region-loss detection signal shall fire when two of three independent probe points outside Frankfurt cannot reach it for 2 min, and a failing Route 53 health check shall alert after 3 min. | test | Alerts `RegionDown` (`probe_success` from us-east-1, us-east-2 and an external point) and `Route53HealthCheckFailing` in `observability/alerts/network/edge.yaml`. | D7, section 21.2, ADR-0017 |
| FR-OBS-12 | A dead man's switch shall fire always, and failing notifications shall be sent through a second independent receiver. | test | `Watchdog` routed to `deadmans-switch` and `AlertmanagerNotificationsFailing` to `fallback-webhook` in `observability/alertmanager/alertmanager.yaml`; `observability/tests/test_alertmanager.py`. | Section 25.4 |
| FR-OBS-13 | Dashboards shall be generated from code in the hierarchy L0 overview, L1 services, L2 platform, L3 data and edge, plus FinOps. | test | `observability/lib/build.py` and `dashboards.py` with `observability/lib/tests`; `observability/dashboards/{l0-overview,l1-services,l2-platform,l3-data,l3-edge,finops}`. | Section 15 (dashboards) |
| FR-OBS-14 | Slow requests shall be shown by request type with links to their traces. | inspection | `observability/dashboards/l1-services/slow-requests.json` from `observability/slo/config/slow-requests.yaml`. | Section 15 |

## On-call and incidents

| ID | Requirement | Verification | Implementation | Source |
|---|---|---|---|---|
| FR-OBS-15 | Alerts shall be routed by severity and team: critical to the critical channel, security-owned and `security` severity to the security channel, warnings to the alerts channel. | test | Routes of `observability/alertmanager/alertmanager.yaml`; `observability/tests/test_alertmanager.py`. | Section 20.6 |
| FR-OBS-16 | Every alert shall link a runbook with symptom, diagnostics, actions and escalation (primary acknowledges within 5 min, secondary at 5 min, incident commander at 15 min). | test | `docs/runbooks/<layer>/<alert>.md`; runbook existence and sections checked by `observability/tests/test_contract.py`. | Section 20.6, section 25.3 |
| FR-OBS-17 | AI agents shall analyse incidents with read-only access to observability and run named runbook actions only after a human confirms. | test | `tools/ai/admin_agent` with `config/admin-agent.yaml`; Bedrock roles of `infra/modules/bedrock-access`. | Section 7 (AIOps), section 23.5 |

## Scaling

| ID | Requirement | Verification | Implementation | Source |
|---|---|---|---|---|
| FR-OBS-18 | Router pods shall scale horizontally between 20 and 90 replicas per cell on CPU at 70%, and an HPA at its maximum shall alert. | test | `autoscaling` of `deploy/charts/router/values.yaml`; `deploy/charts/router/tests/scaling_test.yaml`; alert `HpaAtMaxReplicas`. | Section 8 (replicas and autoscaling) |
| FR-OBS-19 | Node capacity shall be bounded per pool by Karpenter CPU limits, and failures to launch nodes or low free subnet IPs shall alert. | test | `cpu_limits` in `config/environments/*.yaml`; alerts `KarpenterCannotLaunchNodes`, `SubnetFreeIpsLow` (below 20%). | Section 8 |
| FR-OBS-20 | Pod capacity per component shall be derived from the load model and checked against the forecast. | test | `docs/capacity/capacity.py` with `pod-capacity.yaml`, `forecast.yaml` and `docs/capacity/tests`. | Section 8 |

## Load, chaos and smoke tests

| ID | Requirement | Verification | Implementation | Source |
|---|---|---|---|---|
| FR-OBS-21 | Load tests shall use the open model with the 7-calls-per-payment mix against a mock PSP and abort when an SLO threshold breaks. | test | `tests/load/` (scenarios, `lib/options.js`, `mock-psp/`), offline tests `npm test` in `tests/load/tests`; k6 Operator `deploy/platform/k6`. | Section 8 (load tests) |
| FR-OBS-22 | Chaos experiments shall run in stage only, each with a hypothesis, a blast radius of at most one AZ or one cell and a stop condition. | test | `tests/chaos/fis/*.json` validated by `tests/chaos/lib/validate_fis.py` and `guard.py`; `tests/chaos/tests/test_chaos.py`; templates of `infra/modules/fis-experiments`. | Section 8 (chaos engineering) |
| FR-OBS-23 | Experiments shall cover AZ loss, node loss, Spot interruption, Aurora writer failover, MemoryDB failover, MSK broker loss, DNS failure, drainer stall and PSP timeout. | test | `tests/chaos/fis/{az-loss,node-loss,workers-spot-interruption,aurora-writer-failover,memorydb-failover,msk-broker-loss}.json`; `tests/chaos/chaos-mesh/{dns-failure,drainer-stall,psp-timeout}.yaml`. | Section 8 |
| FR-OBS-24 | A full region switch shall be tested every quarter, to us-east-1 and us-east-2 in turn, with the promotion as the only point of no return. | test | `tests/chaos/region-switch/{scenario,plan-b}.json` validated by `runner.py --dry-run`; alert `DrSwitchTestOverdue`; dashboard `l3-data/dr-switch.json`. | D7 |
| FR-OBS-25 | Platform contracts (alerts, telemetry path, chart values schemas, HA) shall be tested offline in CI. | test | `tests/contracts/test_{alert_contracts,telemetry_path,values_schema,platform_ha}.py`. | Section 18 |
