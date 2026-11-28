# data: central logs (OpenSearch)

Runbooks of the central OpenSearch domain `pay-shared-services-euc1-logs` (shared-services): application logs of every environment in `logs-app-<env>` and the audit trail in `logs-audit`. OpenSearch Dashboards is at https://logs.payments.internal (Okta sign-in); every OpenSearch request below runs in its Dev Tools. Shard work is in [shard operations](opensearch-shards.md), the Logstash pipeline in [logstash.md](logstash.md).

## logs-open-search-cluster-red

Alert `LogsOpenSearchClusterRed`, severity critical, owner observability-oncall, failure mode `data-logs-open-search-cluster-red`, dashboard https://grafana.payments.internal/d/logs.

### Symptom

CloudWatch `ClusterStatus.red` of the central domain is 1 for 5 minutes: at least one primary shard is unassigned.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=LogsOpenSearchClusterRed`) runs the read-only step of SSM document `pay-runbook-logs-open-search-cluster-red`.
2. In OpenSearch Dashboards Dev Tools (https://logs.payments.internal): `GET _cluster/health?level=indices` and `GET _cat/indices?v&health=red` name the red indices.
3. `GET _cluster/allocation/explain` gives the reason for the first unassigned primary (disk watermark, shard limit, lost node); see [shard operations](opensearch-shards.md).
4. Check `FreeStorageSpace`, `JVMMemoryPressure` and `Nodes` on the dashboard: a node loss or a full disk is the usual cause.

### Actions

1. Fix the cause first: free storage (`LogsOpenSearchStorageLow`) or add data nodes with document step `scale-opensearch`.
2. Retry the failed allocations with document step `reroute-retry-failed` (`POST _cluster/reroute?retry_failed=true`).
3. A primary that is lost for good (no replica): restore the index from the newest snapshot with document step `restore-index`; for an older `logs-app-*` backing index, deleting it is acceptable after the owner approves (the S3 archive keeps the raw logs).

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-logs-open-search-cluster-red`), which is audited.

### Escalation

Inform security on-call: the domain holds the audit trail (`logs-audit`); the S3 log archive stays the source of truth meanwhile. Default chain: primary acknowledges within 5 min, the secondary is paged at 5 min and the incident commander at 15 min (section 20.6).

### SSM document

`pay-runbook-logs-open-search-cluster-red`

## logs-open-search-cluster-yellow

Alert `LogsOpenSearchClusterYellow`, severity warning, owner observability-oncall, failure mode `data-logs-open-search-cluster-yellow`, dashboard https://grafana.payments.internal/d/logs.

### Symptom

CloudWatch `ClusterStatus.yellow` is 1 for 15 minutes: every primary is assigned, some replicas are not.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=LogsOpenSearchClusterYellow`) runs the read-only step of SSM document `pay-runbook-logs-open-search-cluster-yellow`.
2. In OpenSearch Dashboards Dev Tools (https://logs.payments.internal): `GET _cat/shards?v&h=index,shard,prirep,state,unassigned.reason&s=state` lists the unassigned replicas.
3. `GET _cluster/allocation/explain` explains the first one; a blue/green deployment or a node replacement shows `NODE_LEFT` and heals by itself.

### Actions

1. Wait for a running configuration change or node replacement to finish (`GET _cat/recovery?v&active_only=true`).
2. Otherwise follow [shard operations](opensearch-shards.md): free disk, lower the shard count or retry allocation with document step `reroute-retry-failed`.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-logs-open-search-cluster-yellow`), which is audited.

### Escalation

Ticket to observability; page only if it turns red.

### SSM document

`pay-runbook-logs-open-search-cluster-yellow`

## logs-open-search-jvm-pressure-high

Alert `LogsOpenSearchJvmPressureHigh`, severity warning, owner observability-oncall, failure mode `data-logs-open-search-jvm-pressure-high`, dashboard https://grafana.payments.internal/d/logs.

### Symptom

CloudWatch `JVMMemoryPressure` (maximum over data nodes) is above 80% for 15 minutes.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=LogsOpenSearchJvmPressureHigh`) runs the read-only step of SSM document `pay-runbook-logs-open-search-jvm-pressure-high`.
2. In OpenSearch Dashboards Dev Tools (https://logs.payments.internal): `GET _nodes/stats/jvm,breaker` shows heap and circuit breaker trips per node; `GET _cat/nodes?v&h=name,heap.percent,segments.memory`.
3. Check the shard count per node and very large aggregations in recent searches (`GET _tasks?actions=*search*&detailed`).

### Actions

1. Cancel a runaway search (`POST _tasks/<task_id>/_cancel`).
2. Too many small shards cost heap: merge them with a larger rollover size ([shard operations](opensearch-shards.md)).
3. Sustained pressure: scale the data nodes up through Terraform (`infra/modules/opensearch`, `instance_type`).

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-logs-open-search-jvm-pressure-high`), which is audited.

### Escalation

Ticket to observability; `LogsOpenSearchJvmPressureCritical` pages at 92%.

### SSM document

`pay-runbook-logs-open-search-jvm-pressure-high`

## logs-open-search-jvm-pressure-critical

Alert `LogsOpenSearchJvmPressureCritical`, severity critical, owner observability-oncall, failure mode `data-logs-open-search-jvm-pressure-critical`, dashboard https://grafana.payments.internal/d/logs.

### Symptom

CloudWatch `JVMMemoryPressure` is above 92% for 5 minutes. At this level the service blocks writes (`ClusterIndexWritesBlocked`) and nodes risk out of memory.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=LogsOpenSearchJvmPressureCritical`) runs the read-only step of SSM document `pay-runbook-logs-open-search-jvm-pressure-critical`.
2. In OpenSearch Dashboards Dev Tools (https://logs.payments.internal): `GET _nodes/stats/jvm,breaker` and `GET _tasks?detailed` find the node and the load.
3. Check whether OpenSearch Dashboards users run wide searches over many days of `logs-app-*`.

### Actions

1. Cancel the heaviest searches (`POST _tasks/<task_id>/_cancel`).
2. Clear the field data cache with document step `clear-cache` (`POST _cache/clear?fielddata=true`).
3. Scale the data nodes up with document step `scale-opensearch`; the blue/green change keeps the domain online.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-logs-open-search-jvm-pressure-critical`), which is audited.

### Escalation

Inform security on-call: the domain holds the audit trail (`logs-audit`); the S3 log archive stays the source of truth meanwhile. Default chain: primary acknowledges within 5 min, the secondary is paged at 5 min and the incident commander at 15 min (section 20.6).

### SSM document

`pay-runbook-logs-open-search-jvm-pressure-critical`

## logs-open-search-cpu-high

Alert `LogsOpenSearchCpuHigh`, severity warning, owner observability-oncall, failure mode `data-logs-open-search-cpu-high`, dashboard https://grafana.payments.internal/d/logs.

### Symptom

CloudWatch `CPUUtilization` of the busiest data node is above 80% for 30 minutes.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=LogsOpenSearchCpuHigh`) runs the read-only step of SSM document `pay-runbook-logs-open-search-cpu-high`.
2. In OpenSearch Dashboards Dev Tools (https://logs.payments.internal): `GET _nodes/hot_threads` and `GET _cat/thread_pool/write,search?v`.
3. Compare `IndexingRate` with the Logstash events rate: a log storm from one service shows up as a jump on both.

### Actions

1. A log storm: lower the log level of the noisy service or drop its debug records in the Logstash pipeline (`deploy/platform/logstash`).
2. Uneven load: check that hot shards spread over all nodes ([shard operations](opensearch-shards.md)).
3. Sustained growth: add data nodes through Terraform.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-logs-open-search-cpu-high`), which is audited.

### Escalation

Ticket to observability.

### SSM document

`pay-runbook-logs-open-search-cpu-high`

## logs-open-search-storage-low

Alert `LogsOpenSearchStorageLow`, severity warning, owner observability-oncall, failure mode `data-logs-open-search-storage-low`, dashboard https://grafana.payments.internal/d/logs.

### Symptom

Free storage of the domain (`FreeStorageSpace` sum over `FreeStorageSpace` plus `ClusterUsedSpace`) is below 20% for 10 minutes.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=LogsOpenSearchStorageLow`) runs the read-only step of SSM document `pay-runbook-logs-open-search-storage-low`.
2. In OpenSearch Dashboards Dev Tools (https://logs.payments.internal): `GET _cat/allocation?v` shows disk use per node, `GET _cat/indices?v&s=store.size:desc&h=index,pri,rep,store.size` the largest indices.
3. Check that the ISM policies still delete and move indices to UltraWarm (`GET _plugins/_ism/explain/.ds-logs-app-*`).

### Actions

1. Fix a stuck ISM step first (`LogsOpenSearchIsmFailing`).
2. Delete expired `logs-app-*` backing indices that ISM missed with document step `delete-expired-indices`.
3. Add EBS storage or data nodes through Terraform (`infra/modules/opensearch`, `volume_size`).

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-logs-open-search-storage-low`), which is audited.

### Escalation

Ticket to observability; below the flood stage writes stop and `LogsOpenSearchIndexWritesBlocked` pages.

### SSM document

`pay-runbook-logs-open-search-storage-low`

## logs-open-search-ism-failing

Alert `LogsOpenSearchIsmFailing`, severity warning, owner observability-oncall, failure mode `data-logs-open-search-ism-failing`, dashboard https://grafana.payments.internal/d/logs.

### Symptom

Index State Management is stuck on a data stream for 15 minutes: its newest backing index is older than 2 days (rollover runs daily), or a `logs-app-*` backing index has existed for more than 32 days (ISM deletes it at day 30). The age is how long the exporter has seen the index (`elasticsearch_indices_docs_primary`).

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=LogsOpenSearchIsmFailing`) runs the read-only step of SSM document `pay-runbook-logs-open-search-ism-failing`.
2. In OpenSearch Dashboards Dev Tools (https://logs.payments.internal): `GET _plugins/_ism/explain/.ds-<stream>-*?show_policy=true` and look for `failed: true`, the failed step and `info.message`.
3. `GET _data_stream/<stream>` shows the generation and the write index; `GET _cat/indices/.ds-<stream>-*?v&s=creation.date&h=index,creation.date.string,pri.store.size` the backing indices by age.
4. Common causes: an index without the policy attached, a shard too large to migrate, warm nodes short of storage, a policy edit that left indices on an old version.

### Actions

1. Fix the cause, then retry the failed step with document step `ism-retry` (`POST _plugins/_ism/retry/<index>`).
2. Rollover stuck: roll the stream over with document step `rollover-stream`; attach the policy to indices without it (`POST _plugins/_ism/add/<index> {"policy_id": "logs-app"}`).
3. Delete stuck: delete the expired backing indices with document step `delete-expired-indices`.
4. A policy error: change the policy in `infra/modules/opensearch-indices` and apply through the pipeline; existing indices move through `POST _plugins/_ism/change_policy/<index>`.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-logs-open-search-ism-failing`), which is audited.

### Escalation

Ticket to observability; a stuck rollover grows shards and a stuck delete fills storage.

### SSM document

`pay-runbook-logs-open-search-ism-failing`

## logs-open-search-index-writes-blocked

Alert `LogsOpenSearchIndexWritesBlocked`, severity critical, owner observability-oncall, failure mode `data-logs-open-search-index-writes-blocked`, dashboard https://grafana.payments.internal/d/logs.

### Symptom

CloudWatch `ClusterIndexWritesBlocked` is 1 for 5 minutes: the domain rejects every write. Logstash keeps events in its persistent queue and the audit pipelines retry.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=LogsOpenSearchIndexWritesBlocked`) runs the read-only step of SSM document `pay-runbook-logs-open-search-index-writes-blocked`.
2. In OpenSearch Dashboards Dev Tools (https://logs.payments.internal): `GET _cluster/settings?include_defaults=true&filter_path=**.blocks` and `GET _all/_settings/index.blocks*`.
3. Check free storage and JVM pressure on the dashboard: the service blocks writes when either crosses its limit.

### Actions

1. Free storage or scale with document step `scale-opensearch`; once below the watermark, remove the read-only block with document step `clear-write-block` (`PUT _all/_settings {"index.blocks.read_only_allow_delete": null}`).
2. JVM pressure: follow `logs-open-search-jvm-pressure-critical`.
3. Watch the Logstash queue fill on the dashboard; it drains by itself after the block is gone.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-logs-open-search-index-writes-blocked`), which is audited.

### Escalation

Inform security on-call: the domain holds the audit trail (`logs-audit`); the S3 log archive stays the source of truth meanwhile. Default chain: primary acknowledges within 5 min, the secondary is paged at 5 min and the incident commander at 15 min (section 20.6).

### SSM document

`pay-runbook-logs-open-search-index-writes-blocked`

## logs-open-search-server-errors

Alert `LogsOpenSearchServerErrors`, severity warning, owner observability-oncall, failure mode `data-logs-open-search-server-errors`, dashboard https://grafana.payments.internal/d/logs.

### Symptom

More than 1% of the requests to the domain end with 5xx for 10 minutes.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=LogsOpenSearchServerErrors`) runs the read-only step of SSM document `pay-runbook-logs-open-search-server-errors`.
2. Check `JVMMemoryPressure`, `CPUUtilization` and `ThreadpoolWriteRejected` on the dashboard: 5xx follow overload.
3. Check the domain events in the AWS Health dashboard and the Logstash output errors.

### Actions

1. Overload: follow the CPU or JVM sections; a domain incident: open an AWS support case.
2. Writers retry by themselves; confirm the Logstash queue drains afterwards.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-logs-open-search-server-errors`), which is audited.

### Escalation

Ticket to observability.

### SSM document

`pay-runbook-logs-open-search-server-errors`

## logs-open-search-throttled

Alert `LogsOpenSearchThrottled`, severity warning, owner observability-oncall, failure mode `data-logs-open-search-throttled`, dashboard https://grafana.payments.internal/d/logs.

### Symptom

The write thread pool rejects requests (`ThreadpoolWriteRejected` grows) or EBS throttles the volumes (`ThroughputThrottle`, `IopsThrottle`) within 10 minutes.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=LogsOpenSearchThrottled`) runs the read-only step of SSM document `pay-runbook-logs-open-search-throttled`.
2. In OpenSearch Dashboards Dev Tools (https://logs.payments.internal): `GET _cat/thread_pool/write?v&h=node_name,active,queue,rejected`.
3. Compare the Logstash bulk size and workers (`deploy/platform/logstash/values.yaml`) with the indexing rate; check the gp3 throughput of the volumes.

### Actions

1. Short bursts heal through the Logstash retries.
2. Sustained: raise the gp3 throughput or IOPS through Terraform, or add data nodes; lower `pipeline.workers` of Logstash if one pod floods the domain.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-logs-open-search-throttled`), which is audited.

### Escalation

Ticket to observability.

### SSM document

`pay-runbook-logs-open-search-throttled`

## logs-open-search-snapshot-failing

Alert `LogsOpenSearchSnapshotFailing`, severity warning, owner observability-oncall, failure mode `data-logs-open-search-snapshot-failing`, dashboard https://grafana.payments.internal/d/logs.

### Symptom

CloudWatch `AutomatedSnapshotFailure` is 1: no automated snapshot of the domain was taken in the last 36 hours.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=LogsOpenSearchSnapshotFailing`) runs the read-only step of SSM document `pay-runbook-logs-open-search-snapshot-failing`.
2. In OpenSearch Dashboards Dev Tools (https://logs.payments.internal): `GET _snapshot/_all`, `GET _snapshot/<repository>/_all?verbose=false` and `GET _snapshot/_status`.
3. Check for a red index: a red index fails the snapshot. For the manual S3 repository, check the snapshot role and the bucket policy (`infra/modules/opensearch`).

### Actions

1. Fix the red index first; then take a manual snapshot to the S3 repository with document step `snapshot-now`.
2. Verify the repository with `POST _snapshot/<repository>/_verify`.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-logs-open-search-snapshot-failing`), which is audited.

### Escalation

Ticket to observability and security (the audit trail is in the snapshot).

### SSM document

`pay-runbook-logs-open-search-snapshot-failing`

## logs-audit-ingestion-errors

Alert `LogsAuditIngestionErrors`, severity warning, owner observability-oncall, failure mode `data-logs-audit-ingestion-errors`, dashboard https://grafana.payments.internal/d/logs.

### Symptom

An OpenSearch Ingestion pipeline (`<prefix>-audit-cloudtrail` or `<prefix>-audit-eks`) failed to read objects of the log archive or to write documents to `logs-audit` within 10 minutes.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=LogsAuditIngestionErrors`) runs the read-only step of SSM document `pay-runbook-logs-audit-ingestion-errors`.
2. Read the pipeline logs in `/aws/vendedlogs/OpenSearchIngestion/<pipeline>` for the failing object or the bulk error.
3. Check the pipeline role: S3 and KMS access to the log-archive account (`infra/modules/log-ingestion`) and its mapping to `logs_audit_writer`.
4. In OpenSearch Dashboards Dev Tools (https://logs.payments.internal): `GET logs-audit/_mapping` against the rejected field when documents fail with 400.

### Actions

1. Access errors: fix the role or the bucket policy through Terraform.
2. Mapping errors: fix the processor of the pipeline or the template in `infra/modules/opensearch-indices`.
3. Objects the pipeline skipped are re-read by the next scan once the error is gone; the archive keeps them.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-logs-audit-ingestion-errors`), which is audited.

### Escalation

Ticket to observability and security: audit events are missing from search until the pipeline catches up.

### SSM document

`pay-runbook-logs-audit-ingestion-errors`

## logs-ingestion-stopped

Alert `LogsIngestionStopped`, severity critical, owner observability-oncall, failure mode `data-logs-ingestion-stopped`, dashboard https://grafana.payments.internal/d/logs.

### Symptom

The `logs-app-<env>` data stream of an environment got no new document for 10 minutes (exporter counter `elasticsearch_indices_indexing_index_total`). The fallback stream `logs-app-unknown` is excluded.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=LogsIngestionStopped`) runs the read-only step of SSM document `pay-runbook-logs-ingestion-stopped`.
2. Check the Logstash panels on the dashboard: events in, events out and output errors for pipeline `otlp-logs`.
3. Check the node collectors of that environment: the `otlphttp/central-logs` exporter errors and the gateway `logs` on the central cluster.
4. In OpenSearch Dashboards Dev Tools (https://logs.payments.internal): `GET logs-app-<env>/_search?size=1&sort=@timestamp:desc` confirms the newest document.

### Actions

1. Collectors cannot reach Logstash: check the TLS client certificates and the internal gateway; the collectors buffer and retry.
2. Logstash stalled: follow the Logstash runbook (`logstash.md`).
3. OpenSearch rejects writes: follow `logs-open-search-index-writes-blocked`.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-logs-ingestion-stopped`), which is audited.

### Escalation

Logs of the environment are not searchable: incidents are diagnosed without them. Default chain: primary acknowledges within 5 min, the secondary is paged at 5 min and the incident commander at 15 min (section 20.6).

### SSM document

`pay-runbook-logs-ingestion-stopped`
