# OpenSearch shard operations

Alerts `LogsOpenSearchUnassignedShards` and `LogsOpenSearchShardsPerNodeHigh`, layer data, service opensearch, severity warning, owner observability-oncall, failure modes `data-logs-open-search-unassigned-shards` and `data-logs-open-search-shards-per-node-high`.
Dashboard: https://grafana.payments.internal/d/logs

The central domain `pay-shared-euc1-logs` holds the data streams `logs-app-<env>` and `logs-audit`. Their templates and ISM policies live in `infra/modules/opensearch-indices`: 3 primaries and 1 replica per backing index; `logs-app` rolls over at 30 GB per primary shard or after 1 day, `logs-audit` at 10 GB or 1 day; shard sizes are kept between 10 and 50 GB. Every request below runs in OpenSearch Dashboards Dev Tools (https://logs.payments.internal, Okta sign-in).

## Symptom

- `LogsOpenSearchUnassignedShards`: CloudWatch `Shards.unassigned` of the domain is above 0 for 15 minutes.
- `LogsOpenSearchShardsPerNodeHigh`: a data node holds more than 900 shards (exporter metric `elasticsearch_node_shards_total`) for 15 minutes. The service limit is 1000 shards per data node; at the limit a rollover cannot create its new backing index and ingestion stops.

## Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=LogsOpenSearchUnassignedShards`) runs the read-only step of SSM document `pay-runbook-open-search-shards` and gathers the outputs below.
2. For the shard count: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=LogsOpenSearchShardsPerNodeHigh`) runs the read-only step of SSM document `pay-runbook-open-search-shards`.
3. Look at the shards in Dev Tools:
   - `GET _cat/indices?v&s=index&h=health,index,pri,rep,docs.count,store.size,pri.store.size` lists every index with its health and size; the primary store size divided by `pri` is the shard size.
   - `GET _cat/shards?v&s=store:desc&h=index,shard,prirep,state,docs,store,node,unassigned.reason` lists every shard, its node and, if unassigned, the reason.
   - `GET _cat/allocation?v` shows the shard count and the disk use per node; compare the nodes.
   - `GET _cluster/allocation/explain` explains the first unassigned shard; for a given one: `GET _cluster/allocation/explain {"index": "<index>", "shard": 0, "primary": false}`.
4. Read the explanation: `disk threshold` (the node is above the low watermark), `too many shards` (the per-node limit), `same shard` (no node left in another zone for the replica), `NODE_LEFT` (a node was replaced; it heals after `index.unassigned.node_left.delayed_timeout`).
5. Count small shards: `GET _cat/shards?v&s=store:asc&h=index,shard,prirep,store` — many shards under 1 GB mean the rollover size is too small for the volume of that stream.

## Actions

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-open-search-shards`), which is audited. Template and policy changes go through Terraform (`infra/modules/opensearch-indices`) in a pull request.

### Unassigned shards

1. Fix the reason from the allocation explanation: free disk or add storage (see the `logs-open-search-storage-low` section of [logs-opensearch.md](logs-opensearch.md)), or lower the shard count (below).
2. Retry the allocations that failed five times with document step `reroute-retry-failed` (`POST _cluster/reroute?retry_failed=true`).
3. A replica that cannot be placed because the domain has fewer zones or nodes than copies: set the replicas of the affected backing indices to what the layout allows with document step `set-replicas`, and fix the template in Terraform.

### Rebalance

1. OpenSearch balances by shard count per node, not by size. Check `GET _cat/allocation?v` after a node replacement: the counts should be even within a few shards.
2. Check the balance settings: `GET _cluster/settings?include_defaults=true&filter_path=**.cluster.routing`; `cluster.routing.rebalance.enable` must be `all` and `cluster.routing.allocation.enable` must be `all`.
3. A skewed node: move one large shard with document step `move-shard` (`POST _cluster/reroute {"commands": [{"move": {"index": "<index>", "shard": <n>, "from_node": "<node>", "to_node": "<node>"}}]}`), one at a time, watching `GET _cat/recovery?v&active_only=true`.
4. Hot shards of the write index must spread over all data nodes: the template uses 3 primaries for 3 data nodes; when the data node count changes, change `primary_shards` of the stream to a multiple of it.

### A shard that is too small or too large

The shard size of a data stream is set by its template (primaries) and its ISM rollover condition (size or age). Existing backing indices keep their layout; the fix takes effect at the next rollover.

1. Find the current sizes: `GET _cat/indices/.ds-logs-app-*?v&s=index&h=index,pri,pri.store.size`. The target is 10 to 50 GB per primary shard.
2. Too small (many shards under 10 GB, the shard count per node climbs): lower `primary_shards` of the stream, or raise the rollover age (for example from 1 day to 3 days for a quiet environment), in `infra/modules/opensearch-indices`; merge or delete old small indices once ISM moves them to warm.
3. Too large (shards above 50 GB, slow recovery and warm migration): raise `primary_shards` to the next multiple of the data node count, or lower `rollover_shard_size`.
4. Apply the Terraform change, then roll the stream over at once so the next backing index takes the new template: document step `rollover-stream` (`POST logs-app-<env>/_rollover`).
5. Check the new backing index: `GET _cat/shards/.ds-logs-app-<env>-*?v&s=index:desc` shows the new primary count, and `GET _plugins/_ism/explain/.ds-logs-app-<env>-*` shows the policy attached to it.

### Shards per data node near the limit

1. Most shards come from many small backing indices: apply the "too small" fix above and let ISM delete the expired ones.
2. Delete closed or expired indices that ISM missed with document step `delete-expired-indices`.
3. If the count is legitimate, add data nodes through Terraform (`infra/modules/opensearch`, `data_node_count`); do not raise `cluster.max_shards_per_node`.

## Escalation

Ticket to observability. If unassigned primaries appear, the cluster is red and `LogsOpenSearchClusterRed` pages; if the shard limit stops a rollover, `LogsIngestionStopped` pages.

## SSM document

`pay-runbook-open-search-shards`
