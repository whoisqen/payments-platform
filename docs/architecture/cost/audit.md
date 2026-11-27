# FinOps audit

Findings ranked by monthly saving, measured against the totals before the audit (324,458 USD/month on demand, 280,232 USD/month committed).
Each saving is computed after the findings above it in the same environment.
"Keeps SLOs" refers to the SLOs and recovery targets in `manifests/constraints.yaml`.
All findings except 2 are adopted: the owner rejected finding 2 and keeps a hot standby in us-east-1 ([ADR-0019](../../adr/0019-hot-standby-recovery-region.md)). Three owner decisions on the region model follow the findings in the table. The realized columns are recomputed line by line from [calculator-items.csv](calculator-items.csv). Where the change differs from the audit proposal, the finding says how.

## Ranked findings

| # | Finding | Status | Audit estimate on demand (USD/month) | Realized on demand (USD/month) | Keeps SLOs | Risk |
|---:|---|---|---:|---:|---|---|
| 1 | Stage runs the full prod size 24/7 | adopted: `size_window`, working hours | 133,841 | 97,937 | yes (stage has no SLO) | medium |
| 2 | Warm standby compute and MemoryDB in us-east-1 | rejected by the owner: hot standby kept, [ADR-0019](../../adr/0019-hot-standby-recovery-region.md) | 33,895 | 0 | - | - |
| 3 | Spare cell at the working-cell size (prod) | adopted | 11,260 | 11,260 | yes | low |
| 4 | EKS 1.34 leaves standard support on 2026-12-02 (cost avoided) | adopted: 1.36 | 10,585 | 7,665 avoided | yes | low |
| 5 | Analytics sized above its load (prod) | adopted | 7,736 | 7,768 | yes (analytics RPO 15 min, RTO 4 h) | medium |
| 6 | Locker writer at db.r7g.12xlarge (prod) | adopted | 5,262 | 5,472 | yes | low |
| 7 | Dev has four working cells and recovery-region stacks | adopted | 3,598 | 4,117 | yes | low |
| 8 | Dev runs 24/7 | adopted: `aurora-schedule`, KEDA working hours, `env-up` | 2,652 | 1,068 | yes | low |
| 9 | I/O-Optimized storage on low-I/O clusters (spare, locker) | adopted in every environment | 1,838 | 2,232 | yes | low |
| 10 | Network Firewall in 3 AZs in dev | adopted | 577 | 577 | yes | low |
| 11 | Interface endpoints in VPCs without compute (second recovery region) | adopted, then the region was removed | 394 | 394 | yes | low |
| 12 | Central observability workers pool on demand | adopted: Spot first | 343 | 234 committed | yes | low |
| 13 | EKS control plane logs kept 365 days in CloudWatch | adopted: export to the log archive | 192 | -63 (archive storage) | yes, the archive holds 12 months | low |
| | Owner decision: the second recovery region removed in every environment | adopted | | 3,354 | yes | low |
| | Owner decision: stage and dev run in eu-central-1 alone; stage loses its standby, secondaries and copies | adopted | | 35,330 | yes (stage has no SLO) | low |
| | Owner decision: hot standby at the working size in us-east-1 (prod) instead of the pre-audit warm standby | adopted | | -18,285 | yes; the switch only fences, promotes Aurora, warms the cache and moves traffic | none |
| | Follow-on lines: fewer clusters and nodes lower CloudWatch, GuardDuty and Inspector, net of the Firehose export | | | 2,633 | | |
| | **Total realized (finding 4 is avoided cost, not counted)** | | **201,588** | **153,796** | | |

After the findings and the owner decisions, the estimate is **170,662 USD/month on demand** and **139,898 USD/month committed**: 0.412 and 0.337 USD per 1,000 payments ([README.md](README.md)).
The committed total also includes the new commitment model: Database Savings Plans replace the RDS and OpenSearch Reserved Instances. That model saves 1,353 USD/month less on prod than the reservations did, and it follows class changes.

Where the realized figure differs from the audit estimate:

- 1: stage runs the dev sizes. KEDA scales the cell and locker workloads to zero outside the working window, so their nodes run 60 of 168 hours. `aurora-schedule` stops only clusters without recovery-region secondaries, so the stage Aurora clusters keep running. The cell payments pools are priced at the dev cap of 32 vCPU. The prod-size windows are booked per test through `env-up`, so they are not in the total.
- 2: rejected. The owner requires us-east-1 to take the whole prod load at any moment, so it runs at the working size. Warm standby and pilot light are the rejected alternatives of ADR-0019.
- 6: RDS Proxy is billed for the vCPU of both locker instances, writer and reader.
- Second recovery region: the saving of removing it is **3,354 USD/month on demand** (3,354 committed): prod 3,001 (Aurora secondary storage and replicated I/O, backup and S3 copies, their transfer and Replication Time Control, Security Hub checks, Secrets Manager replicas, DynamoDB replicated writes), stage 276, dev 17, shared-services 40 (ECR replicas) and organization 20 (Security Hub checks).
- Stage and dev in eu-central-1 alone: 33,916 is the pre-audit stage warm standby, and 1,414 the stage us-east-1 lines that remained (Aurora secondaries, egress path, endpoints, copies, ECR replicas).
- Hot standby: the prod us-east-1 compute, MemoryDB, Aurora instances, RDS Proxy and NLB, and the logs and security lines they add, cost 52,201 USD/month on demand (41,015 committed). Against the pre-audit warm standby of 33,916, that is 18,285 more.
- 7: the realized figure also counts the Network Firewall line and the replication transfer of the removed stacks.
- 8: Aurora stops outside the 60-hour working window, and KEDA scales the workloads to zero so that Karpenter removes the payments and cde nodes. Bootstrap, workers, MemoryDB and analytics keep running: the MemoryDB snapshot cycle of section 12 is not part of the change. `env-up` starts dev outside the window.
- 9: Standard storage also applies in stage, in dev and on the recovery-region secondaries.
- 12: Spot moves only the committed column. The on-demand column prices every line on demand.
- 13: control-plane logs stream through Firehose into the log archive (`infra/modules/eks/log-export.tf`). `eks.log_retention_days` in `config/environments/prod.yaml` is still 365, so the CloudWatch saving starts when that value is lowered to 90. Until then, the export adds 81 USD/month: 19 for Firehose, counted in the follow-on lines, and 63 for archive storage.

## Findings

### 1. Stage runs the full prod size 24/7

- Evidence: `manifests/environment.yaml` defines stage as the prod size (4 cells plus spare, same replicas and instance classes), and `config/environments/stage.yaml` implements it by overriding only `eks.spot_pools`. Stage therefore carries every prod size, the us-east-1 standby and the secondaries of a second recovery region, 24/7. Section 12 instead budgets 1 stage cell on a schedule; the repository has no schedule (no `env-up` workflow, KEDA cron or EventBridge schedule).
- Change: an owner decision first, since `manifests/environment.yaml` is human-owned and sets the stage size. Then give stage its own sizes in `config/environments/stage.yaml` (Aurora `db.r7g.large` without readers, MemoryDB `db.t4g.small` with 1 shard, `standby.enabled: false`, MSK, OpenSearch and `analytics_eks` at the dev values, lower `eks.cpu_limits`); lower the replica floors in `deploy/envs/stage/values.yaml`. Add the section 12 schedule (75 of 168 hours) and raise stage to the prod size only for test windows.
- Saving basis: stage at the dev size on the schedule (60% of the 24/7 cost) plus 40 hours a month at the prod size: 14,252 USD/month instead of 148,093.
- Risk: whole-platform load and failover tests need a booked window. Stage takes longer to start: MemoryDB restores from a snapshot (section 12).
- Adopted: `size_window` in `infra/live/stage/env.hcl`. `scheduled` (the default) merges the dev Aurora, MemoryDB and node pool caps over the prod reference, and analytics follows the window. `prod-size` is a booked test window, booked through the `env-up` workflow (`prod_size`) or a pull request, as in `docs/runbooks/compute/stage-test-window.md`. `manifests/environment.yaml` records the owner decision. Stage keeps 4 cells and the spare. By a later owner decision it runs in eu-central-1 alone.

### 2. Warm standby compute and MemoryDB in us-east-1 (prod)

- Evidence: `config/environments/prod.yaml` sets `standby.enabled: true`. `infra/live/prod/us-east-1/cell-*` and `spare` create EKS, Karpenter and MemoryDB, and `deploy/envs/prod/us-east-1/` runs the chart floors there (router 20 pods per cell). D6 says "no standby compute". D7 says MemoryDB is rebuilt from Aurora and compute is created from Terraform at the switch.
- Change: set `standby.enabled: false` and `reader_count: 0` in `config/environments/prod.yaml`. Remove `eks`, `karpenter`, `iam-workloads` and `memorydb` from `infra/live/prod/us-east-1/cell-*` and `spare`, and remove `deploy/envs/prod/us-east-1/`. Keep the Aurora secondaries, the network and the edge.
- Saving: 5 control planes, 33 nodes and their volumes (7,794), 30 MemoryDB nodes (13,512), 6 Aurora readers (12,588).
- Risk: the region switch builds compute and MemoryDB inside the 60-minute RTO. The switch runbook and a timed DR drill must prove it before the change merges.
- Rejected by the owner: warm standby kept, then raised to a hot standby at the working size ([ADR-0019](../../adr/0019-hot-standby-recovery-region.md)). The owner requires us-east-1 to take the whole load at any moment. `standby.compute_enabled: true` in `config/environments/prod.yaml`. The switch fences Frankfurt, promotes Aurora, warms the cache and moves traffic; its critical path is 32 minutes against the 60-minute RTO ([drills](../../dr/drills.md)). Stage has no standby region.

### 3. Spare cell at the working-cell size (prod)

- Evidence: the glossary keeps the spare "in a minimal profile". `infra/live/prod/eu-central-1/spare/aurora/terragrunt.hcl` sets no instance classes, so the spare inherits `db.r7g.12xlarge` plus a `db.r7g.4xlarge` reader. Its MemoryDB has 2 shards, and `deploy/envs/prod/eu-central-1/spare/values.yaml` keeps the router floor of 20 pods.
- Change: set `writer_instance_class` and `reader_instance_class` to `db.r7g.2xlarge` (section 12) in `infra/live/prod/eu-central-1/spare/aurora/terragrunt.hcl`, `num_shards = 1` in `infra/live/prod/eu-central-1/spare/memorydb/terragrunt.hcl`, and `router.autoscaling.minReplicas: 3` in the spare values.
- Risk: the spare must be raised to the prod profile before it takes a hot merchant. That is an instance-class change with a short failover on an empty cell, done in the merchant-move runbook. D8 warm-up still applies.
- Adopted: `db.r7g.2xlarge` writer and reader and `num_shards = 1` in the prod spare stacks. The spare values keep 3 pods of each workload (`minReplicas: 3`) in stage and prod.

### 4. EKS 1.34 leaves standard support on 2026-12-02

- Evidence: `kubernetes_version = "1.34"` in `infra/live/{dev,stage,prod,shared-services}/env.hcl`. The EKS version calendar ends standard support for 1.34 on 2026-12-02, and extended support adds 0.50 USD per cluster-hour (Price List `AmazonEKS-Hours:extendedSupport`).
- Change: upgrade the 29 clusters to 1.35 (standard support until 2027-03-27) and move `bottlerocket_version` with it.
- Risk: a rolling control plane and node upgrade; run dev, then stage, then prod one cell at a time.
- Adopted: all 21 clusters (after finding 7 and with the prod hot standby) run 1.36 (the newest version every pinned add-on supports; 1.37 follows once cert-manager supports it) with Bottlerocket `v1.70.0`. They were upgraded one minor version at a time. The avoided cost is 365 USD/month per cluster, 7,665 for the 21.

### 5. Analytics sized above its load (prod)

- Evidence: the defaults in `infra/live/prod/env.hcl` (`analytics`) give MSK 9 x `kafka.m7g.xlarge` with 2,000 GB each, ClickHouse 4 shards x 2 replicas on `r7g.2xlarge` and OpenSearch 6 x `r7g.xlarge.search`. The event stream at the target load is about 4 TB a month (1.5 MB/s on average). Seven days of retention at replication factor 3 needs about 2.8 TB of broker storage.
- Change: in `config/environments/prod.yaml` set `msk` (3 x `kafka.m7g.large`, 1,000 GB), `opensearch` (3 data nodes) and `analytics_eks`, and halve the ClickHouse shards. Saving: MSK 4,461, ClickHouse 1,890, OpenSearch 1,386.
- Risk: size from 30 days of `BytesInPerSec`, ClickHouse CPU and OpenSearch JVM pressure in CloudWatch and VictoriaMetrics. Resharding ClickHouse needs a planned copy.
- Adopted: the analytics defaults in `infra/live/prod/env.hcl`: MSK 3 x `kafka.m7g.large` with 1,000 GB, 3 OpenSearch data nodes, and a 48 vCPU stateful cap for ClickHouse at 2 shards x 2 replicas.

### 6. Locker writer at db.r7g.12xlarge (prod)

- Evidence: `infra/live/prod/eu-central-1/locker/aurora/terragrunt.hcl` inherits the cell classes. The locker carries 2.4 requests per TPS (384 RPS on average, `docs/capacity/forecast.yaml`). Section 12 sizes it at `db.r7g.4xlarge`.
- Change: set `writer_instance_class = "db.r7g.4xlarge"` in that file and keep the reader. Section 12 adds a second reader, which reduces the saving to 2,735.
- Risk: check CPU and buffer cache hit ratio in Performance Insights over a sale peak first. The locker SLO (99.99%) depends on the reader in another AZ, which stays.
- Adopted: `writer_instance_class = "db.r7g.4xlarge"` in `infra/live/prod/eu-central-1/locker/aurora/terragrunt.hcl`. The reader stays.

### 7. Dev has four working cells and recovery-region stacks

- Evidence: `manifests/environment.yaml` sizes dev as one working cell plus the spare with no recovery regions. `infra/live/dev/eu-central-1/cell-1` to `cell-3` exist, as do Aurora secondaries and VPCs in `infra/live/dev/us-east-1` and in the second recovery region.
- Change: remove those stacks and `deploy/envs/dev/eu-central-1/cell-1` to `cell-3`. Keep `panel-edge` and `waf-edge` in us-east-1.
- Risk: multi-cell routing is then tested in stage only.
- Adopted: dev `cells = ["cell-0", "spare"]`. The dev us-east-1 keeps only `panel-edge`, `waf-edge` and `kms`. ECR and backups do not replicate in dev.

### 8. Dev runs 24/7

- Evidence: no schedule in the repository. Section 12 runs dev 60 of 168 hours.
- Change: KEDA cron in `deploy/envs/dev/`, an EventBridge Scheduler stack that stops Aurora, deletes MemoryDB from a snapshot and restores it, and the `env-up` workflow with a new `deploy/envs/dev/keep-alive.yaml` (section 12). Saving assumes 40% of the remaining dev cost stops.
- Risk: the first start of the day takes minutes; `env-up` covers work outside the window.
- Adopted for Aurora: `infra/live/dev/eu-central-1/aurora-schedule` (EventBridge Scheduler, 08:00-20:00 Europe/Berlin on weekdays) stops and starts the cell-0, spare and locker clusters. AWS stops a cluster of a global database only when it is the only member, so the schedule is limited to dev. `global.workingHours` in `deploy/envs/{dev,stage}/values.yaml` scales the workloads to zero on the same window through KEDA cron. The `env-up` workflow keeps dev (Aurora included) or stage up for 1 to 72 hours through `deploy/envs/<env>/keep-alive.yaml`. The MemoryDB snapshot cycle of section 12 remains open.

### 9. I/O-Optimized storage on low-I/O clusters

- Evidence: `infra/modules/aurora-global/main.tf` hard-codes `storage_type = "aurora-iopt1"`. I/O-Optimized instances cost 30% more and storage 0.268 instead of 0.119 USD/GB-month; it pays off only when I/O charges would exceed about 25% of the cluster bill.
- Change: add a `storage_type` variable to the module and set Aurora Standard for the spare and the locker (after findings 3 and 6). Keep I/O-Optimized on the working cells, where the drainer writes in batches all day. Decide per cluster from 30 days of `VolumeReadIOPs` and `VolumeWriteIOPs` in CloudWatch. The type can change once every 30 days.
- Risk: none for the SLOs; a wrong call costs money, not latency.
- Adopted: `storage_type` of `infra/modules/aurora-global`, set to `aurora` (Standard) for the spare and the locker in dev, stage and prod. Standard bills 0.22 USD per million I/Os. For these two prod clusters together, it stays cheaper below about 9 billion I/Os a month.

### 10. Network Firewall in 3 AZs in dev

- Evidence: `infra/live/dev/eu-central-1/firewall/terragrunt.hcl` maps all three egress subnets (3 x 0.395 USD/hour).
- Change: map one subnet in dev and route the other AZs to it. Stage and prod keep three.
- Risk: dev egress depends on one AZ.
- Adopted: `slice(..., 0, 1)` in `infra/live/dev/eu-central-1/firewall/terragrunt.hcl`. NAT gateways stay in three AZs.

### 11. Interface endpoints in VPCs without compute

- Evidence: the VPCs of the second recovery region in prod and dev used the default 9 interface endpoints in 3 AZs. They held only headless Aurora secondaries and the restore test.
- Change: set `interface_endpoint_services = []` there.
- Risk: the restore test there must reach AWS APIs another way.
- Adopted, then superseded: the owner removed the second recovery region, so its VPCs no longer exist.

### 12. Central observability workers on demand

- Evidence: `central_spot_pools = []` in `infra/live/shared-services/env.hcl`, while its comment allows Spot for the workers pool.
- Change: `central_spot_pools = ["workers"]`. Stateful stores stay on demand.
- Risk: Grafana and Sentry web pods restart on interruption; PDBs keep one replica up.
- Adopted: `infra/modules/karpenter` already lets every workers pool use Spot first, with on-demand fallback. `central_spot_pools` stays `[]`, and its comment now says so.

### 13. EKS control plane logs kept 365 days in CloudWatch

- Evidence: `eks.log_retention_days: 365` in `config/environments/prod.yaml`, inherited by stage.
- Change: subscribe the log groups to the log archive (Object Lock, 1 year), then keep 90 days in CloudWatch. PCI DSS 10.5.1 needs 12 months with 3 months immediately available, and the archive provides both.
- Risk: none once the export runs; without it the change breaks the retention requirement.
- Adopted: `log_archive` of `infra/modules/eks` streams the control-plane log group through Firehose into the log archive (`eks/<cluster>/`, Object Lock 365 days) for every cluster in the working region. A cluster without the export keeps at least 365 days in CloudWatch. Lowering `eks.log_retention_days` to 90 in `config/environments/prod.yaml` takes the CloudWatch saving.

## Checked and left as is

| Topic | Result |
|---|---|
| gp3 against io2 | No io2 or io1 volume exists. Node, OpenSearch, ClickHouse and observability volumes are gp3; vmstorage buys 125 MB/s extra throughput for 18 USD/month. |
| NAT gateways | NAT hours and GB are waived behind the Network Firewall endpoints. S3 and DynamoDB use gateway endpoints, and the AWS APIs use interface endpoints. |
| Cross-AZ traffic | 307 USD/month in prod. Istio topology-aware routing keeps service-to-service calls in the AZ; cache and database traffic to the primary node crosses by design. |
| Log retention elsewhere | Loki 30 days, Tempo 14 days, Sentry 90 days, MSK logs 30 days. Object backups go to Glacier Instant Retrieval after 7 days and Glacier Flexible Retrieval after 14 (D5). |
| Observability storage | 2,887 USD/month for the central cluster, mostly nodes. Storage is under 400 USD/month. |
| MemoryDB working cells | 2 shards x 3 nodes per cell match section 12 and the 3-AZ rule of the module. Cost moves only through reserved nodes. |
| Shield Advanced | Not subscribed. Enabling it in `config/platform.yaml` adds 3,000 USD/month (one subscription per organization). |
| Router autoscaling | The HPA targets 10 RPS per pod until the breakpoint test confirms 60. That adds about 2,300 USD/month on demand at the average load. |

## Commitments

- Commitments follow `manifests/environment.yaml`. Compute Savings Plans cover EKS nodes and Lambda. Database Savings Plans cover Aurora, DynamoDB and OpenSearch. MemoryDB uses reserved nodes, and MSK stays on demand. FinOps buys them, not Terraform.
- Size the Compute Savings Plan from the 30-day minimum hourly EC2 spend in Cost Explorer after these findings settle (section 12: 80% of the floor). Size the Database Savings Plan from the steady Aurora, OpenSearch and DynamoDB spend. The us-east-1 hot-standby instances, nodes and MemoryDB reserved nodes fall under the same commitments.
- Renewal follows the coverage and utilization targets of `manifests/constraints.yaml` (coverage 70-80%, utilization above 95%).
