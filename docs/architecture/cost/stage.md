# Cost of stage

Monthly cost at the target load, from the AWS Price List (eu-central-1, us-east-1, global). Method and assumptions: [README.md](README.md).

- Sizing: `size_window = "scheduled"` in `infra/live/stage/env.hcl` merges the Aurora, MemoryDB and node pool caps of `config/environments/dev.yaml` over `config/environments/prod.yaml`. `config/environments/stage.yaml` sets the Spot pools.
- Stage keeps the prod topology at those sizes: 4 cells, the spare and the locker with `db.r7g.large` writers and no readers, MemoryDB `db.t4g.small` with 1 shard. The spare and the locker use Standard storage.
- The cell payments pools are priced at the dev cap (32 vCPU per working cell), and the spare keeps 3 pods of each workload. KEDA scales the cell and locker workloads to zero outside the working window (`global.workingHours`, 60 of 168 hours), so the payments and cde nodes run 260.71 hours a month. Analytics: MSK 3 x `kafka.m7g.large` with 500 GB, one `m7g.medium.search` node, ClickHouse within a 16 vCPU stateful cap.
- A `size_window = "prod-size"` test window raises stage to the prod sizes for its booked hours. Those hours are not in this total.
- Payments and stateful node pools run on Spot; managed data stores run on demand.
- Traffic lines use test volumes, not the prod load.
- Stage runs in eu-central-1 alone: no standby region, no Aurora secondaries, no cross-region copies. Its us-east-1 holds only `panel-edge`, `waf-edge` and `kms`, like dev.
- Every other line runs 730 hours. `aurora-schedule` runs only in dev today.
- Commitments: none (non-prod is not reserved); the committed column applies the Spot planning rate only.

Total: **12,747 USD/month on demand**, **11,254 USD/month committed**.

## By group

| Group | On-demand (USD/month) | Committed (USD/month) |
|---|---:|---:|
| EKS nodes | 6,132.54 | 4,639.93 |
| Aurora | 2,155.22 | 2,155.22 |
| Network | 1,275.84 | 1,275.84 |
| Logs and security | 1,228.22 | 1,228.22 |
| Analytics | 775.99 | 775.99 |
| MemoryDB | 631.30 | 631.30 |
| EKS | 438.00 | 438.00 |
| Data transfer | 56.00 | 56.00 |
| Backup and S3 | 34.60 | 34.60 |
| Edge | 18.15 | 18.15 |
| Data services | 0.77 | 0.77 |
| **Total** | **12,746.63** | **11,254.02** |

## Line items

Hours are per month (730 for 24/7). Usage lines have no hours: quantity times unit price.

| Group | Region | Service | Resource | Configuration | Quantity | Hours | Unit | Unit price (USD) | Monthly on-demand (USD) | Pricing model | Monthly committed (USD) |
|---|---|---|---|---|---:|---:|---|---:|---:|---|---:|
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-cell-0 writer | db.r7g.large, I/O-Optimized | 1 | 730 | instance-hour | 0.433 | 316.09 | on-demand | 316.09 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-cell-0 storage | I/O-Optimized storage | 200 |  | GB-month | 0.268 | 53.60 | on-demand | 53.60 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-cell-1 writer | db.r7g.large, I/O-Optimized | 1 | 730 | instance-hour | 0.433 | 316.09 | on-demand | 316.09 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-cell-1 storage | I/O-Optimized storage | 200 |  | GB-month | 0.268 | 53.60 | on-demand | 53.60 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-cell-2 writer | db.r7g.large, I/O-Optimized | 1 | 730 | instance-hour | 0.433 | 316.09 | on-demand | 316.09 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-cell-2 storage | I/O-Optimized storage | 200 |  | GB-month | 0.268 | 53.60 | on-demand | 53.60 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-cell-3 writer | db.r7g.large, I/O-Optimized | 1 | 730 | instance-hour | 0.433 | 316.09 | on-demand | 316.09 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-cell-3 storage | I/O-Optimized storage | 200 |  | GB-month | 0.268 | 53.60 | on-demand | 53.60 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-spare writer | db.r7g.large, Standard | 1 | 730 | instance-hour | 0.333 | 243.09 | on-demand | 243.09 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-spare storage | Standard storage | 50 |  | GB-month | 0.119 | 5.95 | on-demand | 5.95 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-locker writer | db.r7g.large, Standard | 1 | 730 | instance-hour | 0.333 | 243.09 | on-demand | 243.09 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-locker storage | Standard storage | 50 |  | GB-month | 0.119 | 5.95 | on-demand | 5.95 |
| Aurora | eu-central-1 | Amazon RDS Proxy | proxies of 6 clusters | billed per vCPU of the cluster instances | 12 | 730 | vCPU-hour | 0.018 | 157.68 | on-demand | 157.68 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | backup storage above the free allowance | 35-day PITR | 900 |  | GB-month | 0.023 | 20.70 | on-demand | 20.70 |
| MemoryDB | eu-central-1 | Amazon MemoryDB | memorydb-cell-0 | db.t4g.small, 1 shard(s) x 3 nodes | 3 | 730 | node-hour | 0.054 | 118.26 | on-demand | 118.26 |
| MemoryDB | eu-central-1 | Amazon MemoryDB | memorydb-cell-1 | db.t4g.small, 1 shard(s) x 3 nodes | 3 | 730 | node-hour | 0.054 | 118.26 | on-demand | 118.26 |
| MemoryDB | eu-central-1 | Amazon MemoryDB | memorydb-cell-2 | db.t4g.small, 1 shard(s) x 3 nodes | 3 | 730 | node-hour | 0.054 | 118.26 | on-demand | 118.26 |
| MemoryDB | eu-central-1 | Amazon MemoryDB | memorydb-cell-3 | db.t4g.small, 1 shard(s) x 3 nodes | 3 | 730 | node-hour | 0.054 | 118.26 | on-demand | 118.26 |
| MemoryDB | eu-central-1 | Amazon MemoryDB | memorydb-spare | db.t4g.small, 1 shard(s) x 3 nodes | 3 | 730 | node-hour | 0.054 | 118.26 | on-demand | 118.26 |
| MemoryDB | eu-central-1 | Amazon MemoryDB | data written | all cells | 200 |  | GB | 0.2 | 40.00 | on-demand | 40.00 |
| EKS | eu-central-1 | Amazon EKS | control planes | 4 cells, spare, analytics | 6 | 730 | cluster-hour | 0.1 | 438.00 | on-demand | 438.00 |
| EKS nodes | eu-central-1 | Amazon EC2 | bootstrap node groups, 3 per cluster | m7g.large, Linux, shared tenancy | 18 | 730 | instance-hour | 0.0978 | 1,285.09 | on-demand | 1,285.09 |
| EKS nodes | eu-central-1 | Amazon EC2 | payments pool, 4 working cells (dev cap 32 vCPU each, working hours) | m7g.4xlarge, Linux, Spot | 8 | 260.71 | instance-hour | 0.7821 | 1,631.21 | Spot at 40% of on-demand | 652.48 |
| EKS nodes | eu-central-1 | Amazon EC2 | payments pool, spare cell (3 pods of each workload) | m7g.2xlarge, Linux, Spot | 1 | 260.71 | instance-hour | 0.391 | 101.94 | Spot at 40% of on-demand | 40.78 |
| EKS nodes | eu-central-1 | Amazon EC2 | workers pool, platform add-ons of 5 cell clusters | m7g.2xlarge, Linux, shared tenancy | 5 | 730 | instance-hour | 0.391 | 1,427.15 | on-demand | 1,427.15 |
| EKS nodes | eu-central-1 | Amazon EC2 | cde pool, locker (working hours) | m7g.xlarge, Linux, shared tenancy | 3 | 260.71 | instance-hour | 0.1955 | 152.91 | on-demand | 152.91 |
| EKS nodes | eu-central-1 | Amazon EC2 | analytics stateful pool (cap 16 vCPU) | r7g.2xlarge, Linux, Spot | 2 | 730 | instance-hour | 0.5168 | 754.53 | Spot at 40% of on-demand | 301.81 |
| EKS nodes | eu-central-1 | Amazon EC2 | analytics workers pool (cap 8 vCPU) | m7g.2xlarge, Linux, shared tenancy | 1 | 730 | instance-hour | 0.391 | 285.43 | on-demand | 285.43 |
| EKS nodes | eu-central-1 | Amazon EBS | ClickHouse data volumes | gp3, 2 x 1,000 GB | 2,000 |  | GB-month | 0.0952 | 190.40 | on-demand | 190.40 |
| EKS nodes | eu-central-1 | Amazon EBS | node volumes (4 GiB OS + 80 GiB data) | gp3, 38 nodes x 84 GB | 3,192 |  | GB-month | 0.0952 | 303.88 | on-demand | 303.88 |
| Analytics | eu-central-1 | Amazon MSK | brokers | kafka.m7g.large, 3 AZ | 3 | 730 | broker-hour | 0.2445 | 535.46 | on-demand | 535.46 |
| Analytics | eu-central-1 | Amazon MSK | broker storage | 3 x 500 GB | 1,500 |  | GB-month | 0.119 | 178.50 | on-demand | 178.50 |
| Analytics | eu-central-1 | Amazon OpenSearch Service | data nodes | m7g.medium.search, 1 AZ | 1 | 730 | instance-hour | 0.081 | 59.13 | on-demand | 59.13 |
| Analytics | eu-central-1 | Amazon OpenSearch Service | data node storage | gp3, 20 GB | 20 |  | GB-month | 0.1452 | 2.90 | on-demand | 2.90 |
| Network | eu-central-1 | Amazon VPC | interface endpoints, workload VPC | 9 services x 3 AZ | 27 | 730 | endpoint-hour | 0.012 | 236.52 | on-demand | 236.52 |
| Network | eu-central-1 | Amazon VPC | interface endpoint data processed | AWS API traffic kept off NAT | 500 |  | GB | 0.01 | 5.00 | on-demand | 5.00 |
| Network | eu-central-1 | AWS Network Firewall | firewall endpoints, egress VPC | 3 AZ | 3 | 730 | endpoint-hour | 0.395 | 865.05 | on-demand | 865.05 |
| Network | eu-central-1 | Amazon VPC | NAT gateways behind the firewall | 3 AZ; hours and GB waived by the firewall endpoints | 3 | 730 | gateway-hour | 0 | 0.00 | on-demand | 0.00 |
| Network | eu-central-1 | Amazon VPC | public IPv4 of the NAT gateways | 3 addresses | 3 | 730 | address-hour | 0.005 | 10.95 | on-demand | 10.95 |
| Network | eu-central-1 | AWS Transit Gateway | VPC attachments, workload and egress | 2 attachments | 2 | 730 | attachment-hour | 0.06 | 87.60 | on-demand | 87.60 |
| Network | eu-central-1 | AWS Network Firewall | traffic processed | PSP calls and outgoing webhooks | 200 |  | GB | 0.065 | 13.00 | on-demand | 13.00 |
| Network | eu-central-1 | AWS Transit Gateway | data processed | egress traffic through two attachments | 400 |  | GB | 0.02 | 8.00 | on-demand | 8.00 |
| Network | global | AWS Global Accelerator | accelerator | fixed fee | 1 | 730 | accelerator-hour | 0.025 | 18.25 | on-demand | 18.25 |
| Network | global | AWS Global Accelerator | DT-Premium, Europe to Europe | API responses | 200 |  | GB | 0.015 | 3.00 | on-demand | 3.00 |
| Network | eu-central-1 | Elastic Load Balancing | NLB of the payments gateway | one per region with cells | 1 | 730 | LB-hour | 0.027 | 19.71 | on-demand | 19.71 |
| Network | eu-central-1 | Elastic Load Balancing | NLB capacity units | average LCU | 2 | 730 | LCU-hour | 0.006 | 8.76 | on-demand | 8.76 |
| Data transfer | eu-central-1 | AWS Data Transfer | out to the internet | PSP requests and API responses, 400 GB, tiered | 1 |  | month | 36 | 36.00 | on-demand | 36.00 |
| Data transfer | eu-central-1 | AWS Data Transfer | cross-AZ | router to MemoryDB and RDS Proxy, producers to MSK | 1,000 |  | GB | 0.02 | 20.00 | on-demand | 20.00 |
| Edge | us-east-1 | Amazon CloudFront | panel distribution, data out | PriceClass_100, Europe | 10 |  | GB | 0.085 | 0.85 | on-demand | 0.85 |
| Edge | us-east-1 | Amazon CloudFront | panel HTTPS requests | Europe | 1,000,000 |  | request | 1.2e-06 | 1.20 | on-demand | 1.20 |
| Edge | us-east-1 | AWS WAF | web ACL | panel | 1 |  | ACL-month | 5 | 5.00 | on-demand | 5.00 |
| Edge | us-east-1 | AWS WAF | rules | managed groups and rate rules | 10 |  | rule-month | 1 | 10.00 | on-demand | 10.00 |
| Edge | us-east-1 | AWS WAF | requests | panel | 1,000,000 |  | request | 6e-07 | 0.60 | on-demand | 0.60 |
| Edge | global | Amazon Route 53 | hosted zone | public zone of the environment | 1 |  | zone-month | 0.5 | 0.50 | on-demand | 0.50 |
| Data services | eu-central-1 | Amazon DynamoDB | merchant-cell map reads | on-demand | 5,000,000 |  | read request unit | 1.525e-07 | 0.76 | on-demand | 0.76 |
| Data services | eu-central-1 | Amazon DynamoDB | merchant-cell map writes | on-demand | 10,000 |  | write request unit | 7.625e-07 | 0.01 | on-demand | 0.01 |
| Backup and S3 | eu-central-1 | Amazon S3 | backup and event archive, Standard (days 0-7) | backups/, exports/, events/ | 100 |  | GB-month | 0.0245 | 2.45 | on-demand | 2.45 |
| Backup and S3 | eu-central-1 | Amazon S3 | Glacier Instant Retrieval (days 7-14) | D5 | 100 |  | GB-month | 0.005 | 0.50 | on-demand | 0.50 |
| Backup and S3 | eu-central-1 | Amazon S3 | Glacier Flexible Retrieval (days 14-35) | D5 | 300 |  | GB-month | 0.00405 | 1.21 | on-demand | 1.21 |
| Backup and S3 | eu-central-1 | Amazon S3 | monthly 7-year archive, Deep Archive | first-year average | 300 |  | GB-month | 0.0018 | 0.54 | on-demand | 0.54 |
| Backup and S3 | eu-central-1 | AWS Backup | Aurora snapshots in the vault | 35 days | 1,300 |  | GB-month | 0.023 | 29.90 | on-demand | 29.90 |
| Logs and security | eu-central-1 | Amazon CloudWatch | EKS control plane logs ingested | 5 log types, 6 clusters | 180 |  | GB | 0.63 | 113.40 | on-demand | 113.40 |
| Logs and security | eu-central-1 | Amazon CloudWatch | log storage | 365-day retention, steady state | 2,190 |  | GB-month | 0.0324 | 70.96 | on-demand | 70.96 |
| Logs and security | eu-central-1 | Amazon Data Firehose | EKS control plane logs to the log archive | subscription filter, Direct PUT ingestion | 180 |  | GB | 0.033 | 5.94 | on-demand | 5.94 |
| Logs and security | eu-central-1 | Amazon CloudWatch | VPC flow logs and firewall logs to S3 | vended log delivery | 150 |  | GB | 0.285 | 42.75 | on-demand | 42.75 |
| Logs and security | eu-central-1 | AWS KMS | customer managed keys | 10 per region with replicas, plus service keys | 40 |  | key-month | 1 | 40.00 | on-demand | 40.00 |
| Logs and security | eu-central-1 | AWS KMS | requests |  | 5,000,000 |  | request | 3e-06 | 15.00 | on-demand | 15.00 |
| Logs and security | eu-central-1 | AWS Secrets Manager | secrets | with replicas | 40 |  | secret-month | 0.4 | 16.00 | on-demand | 16.00 |
| Logs and security | eu-central-1 | Amazon GuardDuty | RDS protection | Aurora vCPU | 12 |  | vCPU-month | 1.23 | 14.76 | on-demand | 14.76 |
| Logs and security | eu-central-1 | Amazon GuardDuty | EKS runtime monitoring | 248 node vCPU, tiered | 1 |  | month | 476.16 | 476.16 | on-demand | 476.16 |
| Logs and security | eu-central-1 | Amazon GuardDuty | CloudTrail, VPC flow and DNS analysis | foundational | 100 |  | GB | 1.15 | 115.00 | on-demand | 115.00 |
| Logs and security | eu-central-1 | AWS Security Hub | security checks | 2 regions | 40,000 |  | check | 0.001 | 40.00 | on-demand | 40.00 |
| Logs and security | eu-central-1 | AWS Config | configuration items | node and ENI churn | 40,000 |  | item | 0.003 | 120.00 | on-demand | 120.00 |
| Logs and security | eu-central-1 | AWS Config | conformance pack evaluations |  | 100,000 |  | evaluation | 0.001 | 100.00 | on-demand | 100.00 |
| Logs and security | eu-central-1 | Amazon Inspector | EC2 scanning | nodes | 38 | 730 | instance-hour | 0.0021 | 58.25 | on-demand | 58.25 |
| **Total** | | | | | | | | | **12,746.63** | | **11,254.02** |
