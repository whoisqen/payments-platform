# FinOps audit

Findings ranked by monthly saving, measured against the totals in [README.md](README.md) (324,458 USD/month on demand, 280,232 USD/month committed).
Savings do not overlap: each is computed after the findings above it in the same environment.
"Keeps SLOs" refers to the SLOs and recovery targets in `manifests/constraints.yaml`.

## Ranked findings

| # | Finding | Saving on-demand (USD/month) | Saving committed (USD/month) | Keeps SLOs | Risk |
|---:|---|---:|---:|---|---|
| 1 | Stage runs the full prod size 24/7 | 133,841 | 124,354 | yes (stage has no SLO) | medium |
| 2 | Warm standby compute and MemoryDB in us-east-1 (prod) | 33,895 | 25,155 | yes, if the switch drill builds compute and MemoryDB within the 60-min RTO (D6, D7) | medium |
| 3 | Spare cell at the working-cell size (prod) | 11,260 | 8,726 | yes | low |
| 4 | EKS 1.34 leaves standard support on 2026-12-02 (cost avoided) | 10,585 | 10,585 | yes | low |
| 5 | Analytics sized above its load (prod) | 7,736 | 7,112 | yes (analytics RPO 15 min, RTO 4 h) | medium |
| 6 | Locker writer at db.r7g.12xlarge (prod) | 5,262 | 4,100 | yes | low |
| 7 | Dev has four working cells and recovery-region stacks | 3,598 | 3,598 | yes | low |
| 8 | Dev runs 24/7 | 2,652 | 2,264 | yes | low |
| 9 | I/O-Optimized storage on low-I/O clusters (spare, locker) | 1,838 | 1,416 | yes | low |
| 10 | Network Firewall in 3 AZs in dev | 577 | 577 | yes | low |
| 11 | Interface endpoints in VPCs without compute (us-east-2) | 394 | 394 | yes | low |
| 12 | Central observability workers pool on demand | 343 | 234 | yes | low |
| 13 | EKS control plane logs kept 365 days in CloudWatch (prod) | 192 | 192 | yes, if exported to the log archive first | low |
| | **Total (finding 4 is avoided cost, not counted)** | **201,588** | **178,124** | | |

After findings 1-3 and 5-13 the estimate is **122,870 USD/month on demand** and **102,108 USD/month committed**: 0.296 and 0.246 USD per 1,000 payments.
Finding 4 keeps that number from rising by 10,585 USD/month in December.

## Findings

### 1. Stage runs the full prod size 24/7

- Evidence: `manifests/environment.yaml` defines stage as the prod size (4 cells plus spare, same replicas and instance classes), and `config/environments/stage.yaml` implements it by overriding only `eks.spot_pools`. Stage therefore carries every prod size, the us-east-1 standby and the us-east-2 secondaries, 24/7. Section 12 instead budgets 1 stage cell on a schedule; the repository has no schedule (no `env-up` workflow, KEDA cron or EventBridge schedule).
- Change: an owner decision first, since `manifests/environment.yaml` is human-owned and sets the stage size. Then give stage its own sizes in `config/environments/stage.yaml` (Aurora `db.r7g.large` without readers, MemoryDB `db.t4g.small` with 1 shard, `standby.enabled: false`, MSK, OpenSearch and `analytics_eks` at the dev values, lower `eks.cpu_limits`); lower the replica floors in `deploy/envs/stage/values.yaml`. Add the section 12 schedule (75 of 168 hours) and raise stage to the prod size only for test windows.
- Saving basis: stage at the dev size on the schedule (60% of the 24/7 cost) plus 40 hours a month at the prod size: 14,252 USD/month instead of 148,093.
- Risk: whole-platform load and failover tests need a booked window. Stage takes longer to start: MemoryDB restores from a snapshot (section 12).

### 2. Warm standby compute and MemoryDB in us-east-1 (prod)

- Evidence: `config/environments/prod.yaml` sets `standby.enabled: true`. `infra/live/prod/us-east-1/cell-*` and `spare` create EKS, Karpenter and MemoryDB, and `deploy/envs/prod/us-east-1/` runs the chart floors there (router 20 pods per cell). D6 says "no standby compute". D7 says MemoryDB is rebuilt from Aurora and compute is created from Terraform at the switch.
- Change: set `standby.enabled: false` and `reader_count: 0` in `config/environments/prod.yaml`. Remove `eks`, `karpenter`, `iam-workloads` and `memorydb` from `infra/live/prod/us-east-1/cell-*` and `spare`, and remove `deploy/envs/prod/us-east-1/`. Keep the Aurora secondaries, the network and the edge.
- Saving: 5 control planes, 33 nodes and their volumes (7,794), 30 MemoryDB nodes (13,512), 6 Aurora readers (12,588).
- Risk: the region switch builds compute and MemoryDB inside the 60-minute RTO. The switch runbook and a timed DR drill must prove it before the change merges.

### 3. Spare cell at the working-cell size (prod)

- Evidence: the glossary keeps the spare "in a minimal profile". `infra/live/prod/eu-central-1/spare/aurora/terragrunt.hcl` sets no instance classes, so the spare inherits `db.r7g.12xlarge` plus a `db.r7g.4xlarge` reader. Its MemoryDB has 2 shards, and `deploy/envs/prod/eu-central-1/spare/values.yaml` keeps the router floor of 20 pods.
- Change: set `writer_instance_class` and `reader_instance_class` to `db.r7g.2xlarge` (section 12) in `infra/live/prod/eu-central-1/spare/aurora/terragrunt.hcl`, `num_shards = 1` in `infra/live/prod/eu-central-1/spare/memorydb/terragrunt.hcl`, and `router.autoscaling.minReplicas: 3` in the spare values.
- Risk: the spare must be raised to the prod profile before it takes a hot merchant. That is an instance-class change with a short failover on an empty cell, done in the merchant-move runbook. D8 warm-up still applies.

### 4. EKS 1.34 leaves standard support on 2026-12-02

- Evidence: `kubernetes_version = "1.34"` in `infra/live/{dev,stage,prod,shared-services}/env.hcl`. The EKS version calendar ends standard support for 1.34 on 2026-12-02, and extended support adds 0.50 USD per cluster-hour (Price List `AmazonEKS-Hours:extendedSupport`).
- Change: upgrade the 29 clusters to 1.35 (standard support until 2027-03-27) and move `bottlerocket_version` with it.
- Risk: a rolling control plane and node upgrade; run dev, then stage, then prod one cell at a time.

### 5. Analytics sized above its load (prod)

- Evidence: the defaults in `infra/live/prod/env.hcl` (`analytics`) give MSK 9 x `kafka.m7g.xlarge` with 2,000 GB each, ClickHouse 4 shards x 2 replicas on `r7g.2xlarge` and OpenSearch 6 x `r7g.xlarge.search`. The event stream at the target load is about 4 TB a month (1.5 MB/s on average). Seven days of retention at replication factor 3 needs about 2.8 TB of broker storage.
- Change: in `config/environments/prod.yaml` set `msk` (3 x `kafka.m7g.large`, 1,000 GB), `opensearch` (3 data nodes) and `analytics_eks`, and halve the ClickHouse shards. Saving: MSK 4,461, ClickHouse 1,890, OpenSearch 1,386.
- Risk: size from 30 days of `BytesInPerSec`, ClickHouse CPU and OpenSearch JVM pressure in CloudWatch and VictoriaMetrics. Resharding ClickHouse needs a planned copy.

### 6. Locker writer at db.r7g.12xlarge (prod)

- Evidence: `infra/live/prod/eu-central-1/locker/aurora/terragrunt.hcl` inherits the cell classes. The locker carries 2.4 requests per TPS (384 RPS on average, `docs/capacity/forecast.yaml`). Section 12 sizes it at `db.r7g.4xlarge`.
- Change: set `writer_instance_class = "db.r7g.4xlarge"` in that file and keep the reader. Section 12 adds a second reader, which reduces the saving to 2,735.
- Risk: check CPU and buffer cache hit ratio in Performance Insights over a sale peak first. The locker SLO (99.99%) depends on the reader in another AZ, which stays.

### 7. Dev has four working cells and recovery-region stacks

- Evidence: `manifests/environment.yaml` sizes dev as one working cell plus the spare with no recovery regions. `infra/live/dev/eu-central-1/cell-1` to `cell-3` exist, as do Aurora secondaries and VPCs in `infra/live/dev/us-east-1` and `us-east-2`.
- Change: remove those stacks and `deploy/envs/dev/eu-central-1/cell-1` to `cell-3`. Keep `panel-edge` and `waf-edge` in us-east-1.
- Risk: multi-cell routing is then tested in stage only.

### 8. Dev runs 24/7

- Evidence: no schedule in the repository. Section 12 runs dev 60 of 168 hours.
- Change: KEDA cron in `deploy/envs/dev/`, an EventBridge Scheduler stack that stops Aurora, deletes MemoryDB from a snapshot and restores it, and the `env-up` workflow with a new `deploy/envs/dev/keep-alive.yaml` (section 12). Saving assumes 40% of the remaining dev cost stops.
- Risk: the first start of the day takes minutes; `env-up` covers work outside the window.

### 9. I/O-Optimized storage on low-I/O clusters

- Evidence: `infra/modules/aurora-global/main.tf` hard-codes `storage_type = "aurora-iopt1"`. I/O-Optimized instances cost 30% more and storage 0.268 instead of 0.119 USD/GB-month; it pays off only when I/O charges would exceed about 25% of the cluster bill.
- Change: add a `storage_type` variable to the module and set Aurora Standard for the spare and the locker (after findings 3 and 6). Keep I/O-Optimized on the working cells, where the drainer writes in batches all day. Decide per cluster from 30 days of `VolumeReadIOPs` and `VolumeWriteIOPs` in CloudWatch. The type can change once every 30 days.
- Risk: none for the SLOs; a wrong call costs money, not latency.

### 10. Network Firewall in 3 AZs in dev

- Evidence: `infra/live/dev/eu-central-1/firewall/terragrunt.hcl` maps all three egress subnets (3 x 0.395 USD/hour).
- Change: map one subnet in dev and route the other AZs to it. Stage and prod keep three.
- Risk: dev egress depends on one AZ.

### 11. Interface endpoints in VPCs without compute

- Evidence: `infra/live/prod/us-east-2/vpc` and `infra/live/dev/us-east-2/vpc` use the default 9 interface endpoints in 3 AZs. The VPCs hold only headless Aurora secondaries and the restore test.
- Change: set `interface_endpoint_services = []` there and let the plan B switch create them with the compute.
- Risk: the restore test in us-east-2 must reach AWS APIs another way, or keep `sts`, `kms` and `logs` only.

### 12. Central observability workers on demand

- Evidence: `central_spot_pools = []` in `infra/live/shared-services/env.hcl`, while its comment allows Spot for the workers pool.
- Change: `central_spot_pools = ["workers"]`. Stateful stores stay on demand.
- Risk: Grafana and Sentry web pods restart on interruption; PDBs keep one replica up.

### 13. EKS control plane logs kept 365 days in CloudWatch

- Evidence: `eks.log_retention_days: 365` in `config/environments/prod.yaml`, inherited by stage.
- Change: subscribe the log groups to the log archive (Object Lock, 1 year), then keep 90 days in CloudWatch. PCI DSS 10.5.1 needs 12 months with 3 months immediately available, and the archive provides both.
- Risk: none once the export runs; without it the change breaks the retention requirement.

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

## Commitments beyond section 12

- RDS 3-year partial upfront for `db.r7g.12xlarge` in eu-central-1 costs 2.1959 USD/hour plus 57,709 USD upfront, an effective 4.39 USD/hour (55% of on-demand) against 77% for 1 year no upfront. Section 12 lists it as a budget-halving step (about 10,000 USD/month). Buy it only after findings 2, 3 and 6 settle the instance classes.
- The Compute Savings Plan should be sized after findings 1-3, from the 30-day minimum hourly spend in Cost Explorer (section 12: 80% of the floor).
