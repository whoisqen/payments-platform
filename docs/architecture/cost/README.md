# Platform cost

Monthly AWS cost of every environment at the target load, built from the AWS public Price List and the sizes in this repository.
Each environment file lists its line items, [calculator.md](calculator.md) shows how to enter them in the AWS Pricing Calculator, and [audit.md](audit.md) ranks the savings.

| File | Content |
|---|---|
| [prod.md](prod.md), [stage.md](stage.md), [dev.md](dev.md) | Line items of the three platform environments |
| [shared-services.md](shared-services.md) | CI runners, registry, admin access |
| [central-observability.md](central-observability.md) | Central metrics, logs, traces and Sentry cluster |
| [organization.md](organization.md) | Management and security accounts: trail, log archive, security services |
| [calculator-items.csv](calculator-items.csv) | All 358 line items in one table, same columns as the files |
| [calculator.md](calculator.md) | AWS Pricing Calculator entry, group by group |
| [audit.md](audit.md) | Findings ranked by monthly saving, with the file to change and the risk |

## Totals

Target load: 160 TPS average (`docs/capacity/forecast.yaml`), so **414.7 million payments per month** (160 x 2,592,000 s).
Hours: 730 per month. Currency: USD. Taxes and AWS Support are not included.

| Environment | On-demand (USD/month) | Committed (USD/month) | On-demand per 1,000 payments | Committed per 1,000 payments |
|---|---:|---:|---:|---:|
| prod | 161,487 | 129,881 | 0.389 | 0.313 |
| stage | 148,093 | 137,441 | 0.357 | 0.331 |
| dev | 10,229 | 9,259 | 0.025 | 0.022 |
| shared-services | 1,385 | 868 | 0.003 | 0.002 |
| central observability | 2,887 | 2,405 | 0.007 | 0.006 |
| organization (management, security) | 378 | 378 | 0.001 | 0.001 |
| **Total** | **324,458** | **280,232** | **0.782** | **0.676** |
| Total after the findings of [audit.md](audit.md) | 122,870 | 102,108 | 0.296 | 0.246 |

Per 1,000 payments divides the monthly cost of the line by 414,720 (thousands of payments per month); non-prod lines are spread over the same payments.

"Committed" applies the price model of architecture section 12:

| Workload | Model in the committed column | Discount from the Price List |
|---|---|---|
| Aurora prod (both regions) | RDS Reserved Instance, 1 year, no upfront; the same discount applies to the I/O-Optimized rate | 23% |
| MemoryDB prod (both regions) | Reserved node, 1 year, no upfront | 32% |
| OpenSearch prod data and master nodes | Reserved instance, 1 year, no upfront | 31% |
| EC2 of prod and central observability | Compute Savings Plan, 1 year, no upfront, covering 80% of the steady hours (section 12) | 24% on the covered part |
| Payments and stateful pools of dev and stage, CI runners | Spot, as configured in `config/environments/*.yaml` and `infra/live/shared-services/env.hcl` | planning rate 60% |
| router and locker above the base, managed stores in non-prod | On-demand | none |

Prod lists no Spot pools (`spot_pools: []`): an interrupted pod during a PSP call leaves the payment in the unknown state.

## What drives cost

| Driver | On-demand (USD/month, all environments) | Share |
|---|---:|---:|
| Aurora: instance classes, I/O-Optimized storage, RDS Proxy, recovery regions | 166,412 | 51% |
| MemoryDB: 2 shards x 3 nodes per cell in two regions | 61,360 | 19% |
| Compute: EKS control planes and nodes, CI runners | 55,358 | 17% |
| Analytics: MSK, OpenSearch (ClickHouse nodes are in compute) | 18,450 | 6% |
| Network and data transfer: firewall, endpoints, transit gateway, accelerator, egress | 11,304 | 3% |
| Logs and security services, observability, backup, registry | 11,573 | 4% |

- Database classes drive the bill. Every Aurora cluster of prod and stage, including the spare and the locker, has a `db.r7g.12xlarge` writer (`config/environments/prod.yaml`).
- Stage repeats prod 24/7: `config/environments/stage.yaml` changes only the node capacity type.
- us-east-1 (the warm standby with EKS, MemoryDB and an Aurora reader per cell, plus the panel edge) costs 37,663 USD/month in prod and 35,321 USD/month in stage.
- Traffic-driven lines are small. At 415 million payments the firewall, transit gateway, internet egress, accelerator and cross-AZ traffic together come to about 3,200 USD/month, 2% of prod.

## Price source

AWS Price List bulk API, regional offer files (`https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/<service>/current/<region>/index.json`) and the Compute Savings Plan rate files, read on 2026-11-26.

| Offer file | Publication date |
|---|---|
| Service index | 2026-11-26 05:42 UTC |
| AmazonEC2 (eu-central-1, us-east-1) | 2026-11-24 23:14 UTC |
| AWSComputeSavingsPlan | 2026-11-24 13:03 UTC |
| AmazonRDS | 2026-11-24 23:30 UTC |
| AmazonES (OpenSearch) | 2026-11-25 15:02 UTC |
| AmazonS3, AmazonCloudWatch, AmazonVPC | 2026-11-25 |
| AWSNetworkFirewall, awswaf | 2026-11-23 |
| AWSDataTransfer, AmazonMSK, AmazonEKS | 2026-11-19, 2026-11-17, 2026-11-11 |
| AmazonGuardDuty, AmazonCloudFront | 2026-10-30, 2026-10-19 |
| AmazonMemoryDB, AWSShield, AWSGlobalAccelerator | 2026-09-11 to 2026-09-16 |

- Regions: eu-central-1 (working region), us-east-1 (standby, CloudFront and WAF), us-east-2 (headless secondaries); global services from the `aws-other` offers.
- Spot prices are not in the Price List. One planning rate applies everywhere: Spot at 40% of the on-demand price. The calculator shows its own historical Spot discount for each instance type.
- NAT gateways sit behind Network Firewall endpoints: the Price List records the NAT discount (`NFW-Discount-Processed-Bytes`), and one NAT hour and GB are waived per firewall endpoint hour and GB, so NAT lines are 0.

## Assumptions

Provisioned sizes come from the repository. Only consumed volumes are assumptions, derived from the forecast:

| Quantity | Value in prod | Basis |
|---|---|---|
| Payments per month | 414,720,000 | 160 TPS x 2,592,000 s |
| Router pods | 20 per cell | target capacity 60 RPS per pod (`docs/capacity`), HPA floor in `deploy/charts/router/values.yaml` |
| Node shapes | 3 x m7g.4xlarge per cell, 3 x m7g.large bootstrap per cluster | pod requests of the charts with the spread over 3 AZs |
| Aurora storage | 2,000 GB per working cell, 100 GB spare, 500 GB locker | hot data; older partitions go to S3 |
| Aurora change volume | 6.2 TB per month, 1.55 billion 4 KB write I/Os | 10 rows per payment (drainer load per TPS) x 1.5 KB |
| MemoryDB data written | 6.2 TB per month | 15 KB per payment |
| Egress through the firewall | 10.4 TB per month | 25 KB per payment: PSP calls and outgoing webhooks |
| API responses to merchants | 8.7 TB per month | 7 requests per payment x 3 KB |
| Cross-AZ traffic | 15.4 TB per month | two thirds of cache, database and MSK traffic leaves the AZ |
| EKS control plane logs | 60 GB per cluster per month | 5 log types, 365-day retention in prod and stage |
| ClickHouse volumes | 8 x 1,000 GB gp3 | 4 shards x 2 replicas |

Stage and dev use test volumes (about 2% of prod traffic). Each line states its quantity, so a different volume is a one-cell change in the CSV.

## Cross-check with architecture section 12

Section 12 estimates about 105,000 USD/month for all environments (0.25 USD per 1,000 payments). It priced the target design; this estimate prices what the repository creates.

| Section 12 line | Section 12 (USD/month) | This estimate, on-demand (USD/month) | Why it differs |
|---|---:|---:|---|
| Aurora, 4 cells, spare, locker, recovery region | 37,000 | 85,316 (prod) | I/O-Optimized instances (+30%); spare and locker at the cell size instead of 2xlarge and 4xlarge; RDS Proxy (5,045); one reader per secondary in us-east-1 (12,588); storage in three regions |
| MemoryDB, 4 cells and spare, second region | 10,000 | 30,984 (prod) | spare has 2 shards; full copy of 30 nodes in us-east-1; data written (1,244) |
| Compute prod | 16,000 | 24,933 (prod EKS and nodes) | includes the ClickHouse nodes and the full-size standby clusters; section 12 has the second region at 30% |
| MSK, ClickHouse, OpenSearch | 9,000 | 8,920 (prod) | close; ClickHouse nodes are counted in compute here |
| Network | 8,000 | 6,621 (prod network and data transfer) | NAT charges are waived behind Network Firewall |
| Shield Advanced | 3,000 | 0 | not subscribed: `security.shield_advanced_enabled` is unset in `config/platform.yaml` |
| Observability | 6,000 | 2,887 | central cluster only; the audit OpenSearch is in analytics |
| Security services | 3,000 | 3,894 (prod logs and security plus organization) | GuardDuty RDS and EKS runtime protection are enabled for every account |
| Backups, logs, S3 | 4,000 | 1,159 (prod) | object backups move to Glacier after 7 and 14 days (D5) |
| Shared services | 3,000 | 1,385 | Vault runs in the cell-0 cluster; k6 Cloud is not an AWS charge |
| Non-prod | 6,000 | 158,322 (stage and dev) | stage is a 24/7 copy of prod; section 12 has 1 stage cell on a schedule |
| **Total** | **105,000** | **324,458** | |

- Section 12 places the recovery region in eu-west-1. Owner decisions D6 and D7 replace it with us-east-1 and us-east-2, which this estimate uses.
- Section 12 adds about 30,000 USD/month for the baseline router capacity of 15 RPS per pod. The router HPA target is 10 RPS per pod today (`deploy/charts/router/values.yaml`, `rpsPerPod: 10`). At the average load that keeps about 28 pods per cell instead of 20: roughly one more m7g.4xlarge per working cell, +2,300 USD/month on demand.
- After the findings of [audit.md](audit.md) the estimate is 122,870 USD/month on demand and 102,108 USD/month committed (0.246 USD per 1,000 payments), in line with section 12.

## Dates that change the totals

- Kubernetes 1.34 leaves EKS standard support on 2026-12-02. From that day each of the 29 clusters costs 0.60 instead of 0.10 USD per hour, +10,585 USD/month in total. Version 1.35 stays in standard support until 2027-03-27.
- Reserved Instances and Savings Plans run for 12 months from purchase; renewal follows the coverage and utilization targets of `manifests/constraints.yaml` (coverage 70-80%, utilization above 95%).
