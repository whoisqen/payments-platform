# data: central log pipeline (Logstash)

Runbooks of the central Logstash (StatefulSet `monitoring/logstash` in shared-services, pipeline `otlp-logs`): the node collectors of every environment send OTLP logs to it, and it writes the `logs-app-<env>` data streams of the central OpenSearch. Each pod has a persistent queue and a dead letter queue on its own volume. Metrics come from the `logstash-exporter` sidecar (v1.x; its `queue_events_queue_size` holds the queue size in bytes).

## logstash-pipeline-stalled

Alert `LogstashPipelineStalled`, severity critical, owner observability-oncall, failure mode `data-logstash-pipeline-stalled`, dashboard https://grafana.payments.internal/d/logs.

### Symptom

Pipeline `otlp-logs` on a Logstash pod accepts events (`events_in` grows) and sends none (`events_out` flat) for 5 minutes.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=LogstashPipelineStalled`) runs the read-only step of SSM document `pay-runbook-logstash-pipeline-stalled`.
2. Check the output errors and the persistent queue fill of the pod on the dashboard.
3. Read the pod log (`monitoring/logstash-N`, container `logstash`) for output, credential (IRSA, SigV4) or worker exceptions.
4. Check the `_node/stats/pipelines/otlp-logs` API of the pod on port 9600 through the exporter sidecar report.

### Actions

1. OpenSearch rejects or blocks writes: follow the OpenSearch runbook; Logstash resumes by itself.
2. Expired IRSA credentials or a stuck worker: restart the pod with document step `restart-logstash-pod`; the persistent queue survives the restart.
3. A bad filter after a pipeline change: roll back the change of `deploy/platform/logstash` through Argo CD.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-logstash-pipeline-stalled`), which is audited.

### Escalation

Logs of every environment stop reaching OpenSearch. Default chain: primary acknowledges within 5 min, the secondary is paged at 5 min and the incident commander at 15 min (section 20.6).

### SSM document

`pay-runbook-logstash-pipeline-stalled`

## logstash-queue-backlog-high

Alert `LogstashQueueBacklogHigh`, severity warning, owner observability-oncall, failure mode `data-logstash-queue-backlog-high`, dashboard https://grafana.payments.internal/d/logs.

### Symptom

The persistent queue of a pod is more than half full for 15 minutes: Logstash receives faster than it writes.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=LogstashQueueBacklogHigh`) runs the read-only step of SSM document `pay-runbook-logstash-queue-backlog-high`.
2. Compare events in and events out per pod; check OpenSearch indexing rate, rejections and CPU.
3. Check for a log storm from one environment or service (`IndexingRate`, the collector exporters).

### Actions

1. OpenSearch is the bottleneck: follow its CPU or throttling sections.
2. A log storm: drop or sample the noisy source in the collector or the Logstash filter.
3. Too few workers: raise `pipeline.workers` or the replicas in `deploy/platform/logstash/values.yaml` (each new pod gets its own queue).

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-logstash-queue-backlog-high`), which is audited.

### Escalation

Ticket to observability; `LogstashQueueNearlyFull` pages at 80%.

### SSM document

`pay-runbook-logstash-queue-backlog-high`

## logstash-queue-nearly-full

Alert `LogstashQueueNearlyFull`, severity critical, owner observability-oncall, failure mode `data-logstash-queue-nearly-full`, dashboard https://grafana.payments.internal/d/logs.

### Symptom

The persistent queue of a pod is more than 80% full for 5 minutes. When it is full, Logstash stops accepting batches and the collectors buffer, then drop logs.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=LogstashQueueNearlyFull`) runs the read-only step of SSM document `pay-runbook-logstash-queue-nearly-full`.
2. Same checks as `logstash-queue-backlog-high`; find the slow stage with the flow metrics of the pod (`worker_utilization`, `queue_backpressure`).

### Actions

1. Remove the bottleneck in OpenSearch first (rejections, blocks, CPU).
2. Add Logstash capacity: more workers or replicas through Argo CD; never delete the queue volume, it holds unsent logs.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-logstash-queue-nearly-full`), which is audited.

### Escalation

Default chain: primary acknowledges within 5 min, the secondary is paged at 5 min and the incident commander at 15 min (section 20.6).

### SSM document

`pay-runbook-logstash-queue-nearly-full`

## logstash-dead-letter-queue-entries

Alert `LogstashDeadLetterQueueEntries`, severity warning, owner observability-oncall, failure mode `data-logstash-dead-letter-queue-entries`, dashboard https://grafana.payments.internal/d/logs.

### Symptom

The dead letter queue of a pod grew in the last 15 minutes, or it is full and drops events: OpenSearch rejected documents (mapping, 400 or 404) or the filter routed records without a service there.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=LogstashDeadLetterQueueEntries`) runs the read-only step of SSM document `pay-runbook-logstash-dead-letter-queue-entries`.
2. Read the newest entries with the `dead_letter_queue` input in a one-off Logstash pod (`path => /usr/share/logstash/data/dead_letter_queue`), or check the rejection reason in the pod log.
3. In OpenSearch Dashboards Dev Tools (https://logs.payments.internal): `GET logs-app-<env>/_mapping/field/<field>` for a mapping conflict.

### Actions

1. Mapping conflict: fix the field in the emitting service or map it in `infra/modules/opensearch-indices`; the new backing index after rollover takes it.
2. Replay the fixed entries with document step `replay-dead-letter-queue`; drop entries that hold no useful log after the owner approves.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-logstash-dead-letter-queue-entries`), which is audited.

### Escalation

Ticket to observability.

### SSM document

`pay-runbook-logstash-dead-letter-queue-entries`

## logstash-output-errors

Alert `LogstashOutputErrors`, severity warning, owner observability-oncall, failure mode `data-logstash-output-errors`, dashboard https://grafana.payments.internal/d/logs.

### Symptom

The OpenSearch output of Logstash had bulk request errors (connection, 429, 5xx; retried) or documents rejected for good (sent to the dead letter queue) within 10 minutes.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=LogstashOutputErrors`) runs the read-only step of SSM document `pay-runbook-logstash-output-errors`.
2. Check the output errors on the dashboard and the OpenSearch throttling and 5xx panels.
3. Read the pod log for `Encountered a retryable error` or `Could not index event`.

### Actions

1. 429: OpenSearch is saturated; follow `logs-open-search-throttled`.
2. 403: the IRSA role or its `logs_app_writer` mapping changed; fix it in `infra/modules/log-ingestion` or `opensearch-indices`.
3. Non-retryable failures go to the dead letter queue: follow `logstash-dead-letter-queue-entries`.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-logstash-output-errors`), which is audited.

### Escalation

Ticket to observability.

### SSM document

`pay-runbook-logstash-output-errors`

## logstash-jvm-heap-high

Alert `LogstashJvmHeapHigh`, severity warning, owner observability-oncall, failure mode `data-logstash-jvm-heap-high`, dashboard https://grafana.payments.internal/d/logs.

### Symptom

JVM heap use of a Logstash pod is above 85% for 15 minutes.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=LogstashJvmHeapHigh`) runs the read-only step of SSM document `pay-runbook-logstash-jvm-heap-high`.
2. Check the heap and GC time on the dashboard and the batch size times workers (`pipeline.batchSize`, `pipeline.workers`): in-flight events live on the heap.
3. Look for very large records (long bodies) in the pod log.

### Actions

1. Lower `batchSize` or raise `heap` with the container memory limit in `deploy/platform/logstash/values.yaml`.
2. Restart the pod with document step `restart-logstash-pod` if it is close to out of memory; the persistent queue keeps its events.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-logstash-jvm-heap-high`), which is audited.

### Escalation

Ticket to observability.

### SSM document

`pay-runbook-logstash-jvm-heap-high`

## logstash-pod-down

Alert `LogstashPodDown`, severity warning, owner observability-oncall, failure mode `data-logstash-pod-down`, dashboard https://grafana.payments.internal/d/logs.

### Symptom

The StatefulSet `monitoring/logstash` has fewer ready pods than replicas for 5 minutes.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=LogstashPodDown`) runs the read-only step of SSM document `pay-runbook-logstash-pod-down`.
2. `kubectl -n monitoring describe pod logstash-N` (read-only) for scheduling, volume or probe failures; the pod log for start-up errors.
3. A volume problem: the pod is bound to its EBS volume in one zone.

### Actions

1. Fix the start-up error (configuration, TLS secret, IRSA) through Argo CD.
2. A node or zone problem: Karpenter replaces the node; the pod returns with its queue.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-logstash-pod-down`), which is audited.

### Escalation

Ticket to observability; the other pods keep ingesting, and the pod's queued events wait until it is back.

### SSM document

`pay-runbook-logstash-pod-down`
