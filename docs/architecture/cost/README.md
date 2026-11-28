# Platform cost

Monthly AWS cost of every environment at the target load, built from the AWS public Price List and the sizes in this repository.
Each environment file lists its line items, [calculator.md](calculator.md) shows how to enter them in the AWS Pricing Calculator, and [audit.md](audit.md) ranks the savings.

| File | Content |
|---|---|
| [prod.md](prod.md), [stage.md](stage.md), [dev.md](dev.md) | Line items of the three platform environments |
| [shared-services.md](shared-services.md) | CI runners, registry, admin access |
| [central-observability.md](central-observability.md) | Central metrics, traces and Sentry cluster, and the central log domain |
| [organization.md](organization.md) | Management and security accounts: trail, log archive, security services |
| [calculator-items.csv](calculator-items.csv) | All 293 line items in one table, same columns as the files |
| [calculator.md](calculator.md) | AWS Pricing Calculator entry, group by group |
| [audit.md](audit.md) | Findings ranked by monthly saving, with the file to change and the risk |

## Totals

Target load: 160 TPS average (`docs/capacity/forecast.yaml`), so **414.7 million payments per month** (160 x 2,592,000 s).
Hours: 730 per month. Currency: USD. Taxes and AWS Support are not included.
The totals include every adopted finding of [audit.md](audit.md) and the owner decisions on the region model: two regions, a hot standby in us-east-1 for prod only.

| Environment | On-demand (USD/month) | Committed (USD/month) | On-demand per 1,000 payments | Committed per 1,000 payments |
|---|---:|---:|---:|---:|
| prod | 146,889 | 119,346 | 0.354 | 0.288 |
| stage (`size_window = "scheduled"`) | 12,711 | 11,218 | 0.031 | 0.027 |
| dev | 4,203 | 3,967 | 0.010 | 0.010 |
| shared-services | 1,325 | 808 | 0.003 | 0.002 |
| central observability, with the central log domain | 8,021 | 6,858 | 0.019 | 0.017 |
| organization (management, security) | 421 | 421 | 0.001 | 0.001 |
| **Total** | **173,570** | **142,618** | **0.419** | **0.344** |
| Total before the findings of [audit.md](audit.md) | 324,458 | 280,232 | 0.782 | 0.676 |

Per 1,000 payments divides the monthly cost of the line by 414,720 (thousands of payments per month). Non-prod lines are spread over the same payments.
Stage hours at `size_window = "prod-size"` (booked load test windows, [stage.md](stage.md)) come on top of the stage line.

"Committed" applies the commitments chosen for prod (`manifests/environment.yaml`, `commitments`):

| Workload | Model in the committed column | Discount from the Price List |
|---|---|---|
| Aurora prod instances (eu-central-1 and the us-east-1 hot standby) | Database Savings Plan, 1 year, no upfront, at the plan rate of each instance class and storage type | 20% |
| OpenSearch data and master nodes of the central log domain | Database Savings Plan, 1 year, no upfront | 20% |
| DynamoDB prod requests | Database Savings Plan, 1 year, no upfront | 18% |
| MemoryDB prod | Reserved node, 1 year, no upfront (no Savings Plan covers MemoryDB) | 32% |
| EC2 of prod and central observability, Lambda | Compute Savings Plan, 1 year, no upfront, covering 80% of the steady hours (section 12) | 24% on the covered part |
| MSK, RDS Proxy, UltraWarm, OpenSearch Ingestion | On-demand: no Savings Plan or reservation covers them | none |
| Payments and stateful pools of dev and stage, workers pool of central observability, CI runners | Spot, as configured in `config/environments/*.yaml`, `infra/modules/karpenter` and `infra/live/shared-services/env.hcl` | planning rate 60% |
| router and locker above the base, managed stores in non-prod | On-demand | none |

- The Database Savings Plan rates come from the `AWSDatabaseSavingsPlans` offer of 2026-11-26, for example 8.3048 instead of 10.381 USD/hour for `db.r7g.12xlarge` I/O-Optimized and 2.1296 instead of 2.662 for `db.r7g.4xlarge` Standard.
- At 20%, the Database Savings Plan saves 1,353 USD/month less on prod Aurora than the 1-year RDS Reserved Instances it replaces (23%). In return it covers DynamoDB and OpenSearch, and it follows class changes such as the spare and locker resizes.
- The Lambda functions (`dr-failover`, schedulers) cost under 1 USD/month at their call rates. They have no line of their own, and the Compute Savings Plan covers them.

Prod lists no Spot pools (`spot_pools: []`): an interrupted pod during a PSP call leaves the payment in the unknown state.

## What drives cost

| Driver | On-demand (USD/month, all environments) | Share |
|---|---:|---:|
| Aurora: instance classes in both regions, I/O-Optimized storage of the working cells, RDS Proxy, standby storage | 87,350 | 50% |
| Compute: EKS control planes and nodes in both prod regions, CI runners | 34,484 | 20% |
| MemoryDB: 2 shards x 3 nodes per working cell, in eu-central-1 and the us-east-1 hot standby | 28,882 | 17% |
| Network and data transfer: firewall, endpoints, transit gateway, accelerator, egress | 8,540 | 5% |
| Logs and security services, observability storage, backup, registry, edge | 6,980 | 4% |
| Central log domain: OpenSearch, OpenSearch Ingestion, Logstash queues | 5,156 | 3% |
| Analytics: MSK (ClickHouse nodes are in compute) | 2,178 | 1% |

- Database classes still drive the bill. The four working cells of prod keep a `db.r7g.12xlarge` writer and a `db.r7g.4xlarge` reader on I/O-Optimized storage (`config/environments/prod.yaml`). The spare runs `db.r7g.2xlarge` and the locker `db.r7g.4xlarge`, both on Standard storage.
- Stage runs the dev sizes by default (`size_window = "scheduled"` in `infra/live/stage/env.hcl`) and the prod sizes only in booked test windows. In dev and stage, KEDA scales the cell and locker workloads to zero outside the working window (`global.workingHours`, 60 of 168 hours), and Karpenter removes their nodes. The dev Aurora clusters stop on the same window (`aurora-schedule`).
- The us-east-1 hot standby runs the prod cells at the working size: 5 clusters with the same node pools, MemoryDB, and one Aurora instance per cluster with the writer class of its working cluster ([ADR-0019](../../adr/0019-hot-standby-recovery-region.md)). With its data replicas, egress path and panel edge, the prod us-east-1 lines come to 54,822 USD/month on demand, about 37% of the prod bill. Stage and dev have no standby region.
- Logs: one central OpenSearch domain in shared-services replaces the per-environment OpenSearch domains and the object store of the earlier log stack. It removes 2,226 USD/month from prod, stage and dev (each keeps a 26 USD/month VPC endpoint to the domain) and adds 5,134 to central observability: +2,908 USD/month on demand net, for 30 days of application logs and 365 days of searchable audit trail.
- Traffic-driven lines are small. At 415 million payments, the firewall, transit gateway, internet egress, accelerator and cross-AZ traffic together come to about 3,200 USD/month.

## Price source

AWS Price List bulk API, regional offer files (`https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/<service>/current/<region>/index.json`) and the Compute and Database Savings Plan rate files, read on 2026-11-26. The Database Savings Plan rates, the Aurora Standard rates and the Firehose rate were read on 2026-11-27.

| Offer file | Publication date |
|---|---|
| Service index | 2026-11-26 05:42 UTC |
| AmazonEC2 (eu-central-1, us-east-1) | 2026-11-24 23:14 UTC |
| AWSComputeSavingsPlan | 2026-11-24 13:03 UTC |
| AWSDatabaseSavingsPlans | 2026-11-26 01:17 UTC |
| AmazonKinesisFirehose (eu-central-1) | read 2026-11-27 |
| AmazonRDS | 2026-11-24 23:30 UTC |
| AmazonES (OpenSearch, OpenSearch Ingestion) | 2026-11-25 15:02 UTC |
| AmazonS3, AmazonCloudWatch, AmazonVPC | 2026-11-25 |
| AWSNetworkFirewall, awswaf | 2026-11-23 |
| AWSDataTransfer, AmazonMSK, AmazonEKS | 2026-11-19, 2026-11-17, 2026-11-11 |
| AmazonGuardDuty, AmazonCloudFront | 2026-10-30, 2026-10-19 |
| AmazonMemoryDB, AWSShield, AWSGlobalAccelerator | 2026-09-11 to 2026-09-16 |

- Regions: eu-central-1 (working region), us-east-1 (prod hot standby, CloudFront and WAF); global services from the `aws-other` offers. The us-east-1 Aurora instance rates are derived from the `db.r7g.4xlarge` I/O-Optimized rate of the offer file: linear in size, Standard at the I/O-Optimized rate divided by 1.3, the relation the eu-central-1 rates show. The us-east-1 RDS Proxy rate of 0.015 USD per vCPU-hour is assumed from the public price page, not read from an offer file.
- Spot prices are not in the Price List. One planning rate applies everywhere: Spot at 40% of the on-demand price. The calculator shows its own historical Spot discount for each instance type.
- NAT gateways sit behind Network Firewall endpoints: the Price List records the NAT discount (`NFW-Discount-Processed-Bytes`), and one NAT hour and GB are waived per firewall endpoint hour and GB, so NAT lines are 0.

## Assumptions

Provisioned sizes come from the repository. Only consumed volumes are assumptions, derived from the forecast:

| Quantity | Value in prod | Basis |
|---|---|---|
| Payments per month | 414,720,000 | 160 TPS x 2,592,000 s |
| Router pods | 20 per working cell, 3 in the spare | target capacity 60 RPS per pod (`docs/capacity`), HPA floor in `deploy/charts/router/values.yaml` |
| Node shapes | 3 x m7g.4xlarge per cell, 3 x m7g.large bootstrap per cluster | pod requests of the charts with the spread over 3 AZs |
| Aurora storage | 2,000 GB per working cell, 100 GB spare, 500 GB locker | hot data; older partitions go to S3 |
| Aurora I/O of the spare and the locker | not priced | Standard storage bills 0.22 USD per million I/Os in eu-central-1. Standard stays cheaper than I/O-Optimized for these two clusters below about 9 billion I/Os a month together (1,988 USD/month of saving). Check this against 30 days of `VolumeReadIOPs` and `VolumeWriteIOPs` |
| Aurora change volume | 6.2 TB per month, 1.55 billion 4 KB write I/Os | 10 rows per payment (drainer load per TPS) x 1.5 KB |
| MemoryDB data written | 6.2 TB per month | 15 KB per payment |
| Egress through the firewall | 10.4 TB per month | 25 KB per payment: PSP calls and outgoing webhooks |
| API responses to merchants | 8.7 TB per month | 7 requests per payment x 3 KB |
| Cross-AZ traffic | 15.4 TB per month | two thirds of cache, database and MSK traffic leaves the AZ |
| EKS control plane logs | 60 GB per cluster per month in prod, 30 in stage, 10 in dev | 5 log types; 365-day CloudWatch retention in prod and stage; streamed through Firehose to the log archive (90 days Standard, then Glacier Flexible) |
| ClickHouse volumes | 4 x 1,000 GB gp3 | 2 shards x 2 replicas |
| Central log volume | application logs 30 GB a day, audit 30 GB a day (all environments) | `logs_domain` of `infra/live/shared-services/env.hcl`: 900 GB a month of application logs; EKS control plane 870 GB a month over prod, stage and dev plus 50 GB of CloudTrail |
| MSK | 3 x `kafka.m7g.large`, 1,000 GB each | about 4 TB of events a month; 7 days at replication factor 3 is about 2.8 TB |

Stage and dev use test volumes (about 2% of prod traffic). Each line states its quantity, so a different volume is a one-cell change in the CSV.

## Cross-check with architecture section 12

Section 12 estimates about 105,000 USD/month for all environments (0.25 USD per 1,000 payments). It priced the target design; this estimate prices what the repository creates.

| Section 12 line | Section 12 (USD/month) | This estimate, on-demand (USD/month) | Why it differs |
|---|---:|---:|---|
| Aurora, 4 cells, spare, locker, recovery region | 37,000 | 84,819 (prod) | I/O-Optimized instances (+30%) on the working cells; RDS Proxy in both regions (6,360); one instance at the writer class per hot-standby secondary |
| MemoryDB, 4 cells and spare, second region | 10,000 | 28,010 (prod) | full size in both regions (hot standby); data written (1,244) |
| Compute prod | 16,000 | 22,780 (prod EKS and nodes) | includes the ClickHouse nodes; the us-east-1 hot standby runs the working-region pools |
| MSK, ClickHouse, OpenSearch | 9,000 | 892 (prod MSK, without ClickHouse nodes) | sized to the measured event volume; ClickHouse nodes are counted in compute here; OpenSearch is the central log domain under observability |
| Network | 8,000 | 6,073 (prod network and data transfer) | NAT charges are waived behind Network Firewall |
| Shield Advanced | 3,000 | 0 | not subscribed: `security.shield_advanced_enabled` is unset in `config/platform.yaml` |
| Observability | 6,000 | 8,021 | central cluster and the central log domain for every environment and the audit trail |
| Security services | 3,000 | 3,935 (prod logs and security plus organization) | GuardDuty RDS and EKS runtime protection are enabled for every account |
| Backups, logs, S3 | 4,000 | 764 (prod) | object backups move to Glacier after 7 and 14 days (D5) |
| Shared services | 3,000 | 1,325 | Vault runs in the cell-0 cluster; k6 Cloud is not an AWS charge |
| Non-prod | 6,000 | 16,914 (stage and dev) | stage keeps 4 cells and the spare at the dev sizes in eu-central-1 alone, with cell nodes only in working hours; section 12 has 1 stage cell on a schedule |
| **Total** | **105,000** | **173,570** | |

- Section 12 places the recovery region in eu-west-1. Owner decisions D6 and D7 replace it with us-east-1, the only standby region, which this estimate uses.
- Section 12 adds about 30,000 USD/month for the baseline router capacity of 15 RPS per pod. The router HPA target is 10 RPS per pod today (`deploy/charts/router/values.yaml`, `rpsPerPod: 10`). At the average load, that keeps about 28 pods per cell instead of 20: roughly one more m7g.4xlarge per working cell, +2,300 USD/month on demand.
- The estimate is 173,570 USD/month on demand and 142,618 USD/month committed (0.344 USD per 1,000 payments committed). It is above the 0.25 of section 12 because the owner keeps a hot standby at the working size in us-east-1: 54,822 USD/month on demand in its own lines.

## Dates that change the totals

- All 21 clusters run Kubernetes 1.36, the newest version every pinned add-on supports (cert-manager 1.21 stops at 1.36) (`kubernetes_version` in `infra/live/{dev,stage,prod,shared-services}/env.hcl`). They were upgraded one minor version at a time, which is the only path EKS allows; 1.37 follows once cert-manager supports it. A cluster that stays on a version past its end of standard support pays 0.60 instead of 0.10 USD per hour, +365 USD/month per cluster and +7,665 USD/month for all 21. Plan the next upgrade from the EKS version calendar before that date.
- Savings Plans and MemoryDB reserved nodes run for 12 months from purchase; renewal follows the coverage and utilization targets of `manifests/constraints.yaml` (coverage 70-80%, utilization above 95%).
