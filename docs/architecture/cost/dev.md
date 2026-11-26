# Cost of dev

Monthly cost at the target load, from the AWS Price List (eu-central-1, us-east-1, us-east-2, global). Method and assumptions: [README.md](README.md).

- Sizing: `config/environments/dev.yaml` over `config/environments/prod.yaml`, stacks in `infra/live/dev/`.
- The stacks create four working cells and the spare (`infra/live/dev/eu-central-1/cell-*`, `spare`), each with Aurora `db.r7g.large` (no readers), MemoryDB `db.t4g.small` (1 shard x 3 nodes) and its own EKS cluster.
- Aurora global secondaries without instances exist in us-east-1 and us-east-2 (`infra/live/dev/us-east-*/`).
- Payments and stateful node pools run on Spot; the cde and workers pools run on demand.
- Every line runs 730 hours: the repository has no schedule that stops dev (see [audit.md](audit.md)).
- Commitments: none; the committed column applies the Spot planning rate only.

Total: **10,229 USD/month on demand**, **9,259 USD/month committed**.

## By group

| Group | On-demand (USD/month) | Committed (USD/month) |
|---|---:|---:|
| EKS nodes | 4,157.30 | 3,187.83 |
| Aurora | 2,144.78 | 2,144.78 |
| Network | 1,644.66 | 1,644.66 |
| Analytics | 633.19 | 633.19 |
| MemoryDB | 595.30 | 595.30 |
| Logs and security | 580.13 | 580.13 |
| EKS | 438.00 | 438.00 |
| Edge | 16.83 | 16.83 |
| Data transfer | 13.80 | 13.80 |
| Backup and S3 | 4.37 | 4.37 |
| Data services | 0.16 | 0.16 |
| **Total** | **10,228.52** | **9,259.05** |

## Line items

Hours are per month (730 for 24/7). Usage lines have no hours: quantity times unit price.

| Group | Region | Service | Resource | Configuration | Quantity | Hours | Unit | Unit price (USD) | Monthly on-demand (USD) | Pricing model | Monthly committed (USD) |
|---|---|---|---|---|---:|---:|---|---:|---:|---|---:|
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-cell-0 writer | db.r7g.large, I/O-Optimized | 1 | 730 | instance-hour | 0.433 | 316.09 | on-demand | 316.09 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-cell-0 storage | I/O-Optimized storage | 20 |  | GB-month | 0.268 | 5.36 | on-demand | 5.36 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-cell-1 writer | db.r7g.large, I/O-Optimized | 1 | 730 | instance-hour | 0.433 | 316.09 | on-demand | 316.09 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-cell-1 storage | I/O-Optimized storage | 20 |  | GB-month | 0.268 | 5.36 | on-demand | 5.36 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-cell-2 writer | db.r7g.large, I/O-Optimized | 1 | 730 | instance-hour | 0.433 | 316.09 | on-demand | 316.09 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-cell-2 storage | I/O-Optimized storage | 20 |  | GB-month | 0.268 | 5.36 | on-demand | 5.36 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-cell-3 writer | db.r7g.large, I/O-Optimized | 1 | 730 | instance-hour | 0.433 | 316.09 | on-demand | 316.09 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-cell-3 storage | I/O-Optimized storage | 20 |  | GB-month | 0.268 | 5.36 | on-demand | 5.36 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-spare writer | db.r7g.large, I/O-Optimized | 1 | 730 | instance-hour | 0.433 | 316.09 | on-demand | 316.09 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-spare storage | I/O-Optimized storage | 20 |  | GB-month | 0.268 | 5.36 | on-demand | 5.36 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-locker writer | db.r7g.large, I/O-Optimized | 1 | 730 | instance-hour | 0.433 | 316.09 | on-demand | 316.09 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-locker storage | I/O-Optimized storage | 20 |  | GB-month | 0.268 | 5.36 | on-demand | 5.36 |
| Aurora | eu-central-1 | Amazon RDS Proxy | proxies of 6 clusters | billed per vCPU of the cluster instances | 12 | 730 | vCPU-hour | 0.018 | 157.68 | on-demand | 157.68 |
| Aurora | us-east-1 | Amazon Aurora PostgreSQL | global secondaries storage, 6 clusters | I/O-Optimized storage | 120 |  | GB-month | 0.225 | 27.00 | on-demand | 27.00 |
| Aurora | us-east-1 | Amazon Aurora PostgreSQL | replicated write I/O into this region | Aurora Global Database | 10,000,000 |  | I/O | 2.2e-07 | 2.20 | on-demand | 2.20 |
| Data transfer | eu-central-1 | AWS Data Transfer | Aurora global replication to us-east-1 | inter-region | 20 |  | GB | 0.02 | 0.40 | on-demand | 0.40 |
| Aurora | us-east-2 | Amazon Aurora PostgreSQL | global secondaries storage, 6 clusters | I/O-Optimized storage | 120 |  | GB-month | 0.225 | 27.00 | on-demand | 27.00 |
| Aurora | us-east-2 | Amazon Aurora PostgreSQL | replicated write I/O into this region | Aurora Global Database | 10,000,000 |  | I/O | 2.2e-07 | 2.20 | on-demand | 2.20 |
| Data transfer | eu-central-1 | AWS Data Transfer | Aurora global replication to us-east-2 | inter-region | 20 |  | GB | 0.02 | 0.40 | on-demand | 0.40 |
| MemoryDB | eu-central-1 | Amazon MemoryDB | memorydb-cell-0 | db.t4g.small, 1 shard(s) x 3 nodes | 3 | 730 | node-hour | 0.054 | 118.26 | on-demand | 118.26 |
| MemoryDB | eu-central-1 | Amazon MemoryDB | memorydb-cell-1 | db.t4g.small, 1 shard(s) x 3 nodes | 3 | 730 | node-hour | 0.054 | 118.26 | on-demand | 118.26 |
| MemoryDB | eu-central-1 | Amazon MemoryDB | memorydb-cell-2 | db.t4g.small, 1 shard(s) x 3 nodes | 3 | 730 | node-hour | 0.054 | 118.26 | on-demand | 118.26 |
| MemoryDB | eu-central-1 | Amazon MemoryDB | memorydb-cell-3 | db.t4g.small, 1 shard(s) x 3 nodes | 3 | 730 | node-hour | 0.054 | 118.26 | on-demand | 118.26 |
| MemoryDB | eu-central-1 | Amazon MemoryDB | memorydb-spare | db.t4g.small, 1 shard(s) x 3 nodes | 3 | 730 | node-hour | 0.054 | 118.26 | on-demand | 118.26 |
| MemoryDB | eu-central-1 | Amazon MemoryDB | data written | all cells | 20 |  | GB | 0.2 | 4.00 | on-demand | 4.00 |
| EKS | eu-central-1 | Amazon EKS | control planes | 4 cells, spare, analytics | 6 | 730 | cluster-hour | 0.1 | 438.00 | on-demand | 438.00 |
| EKS nodes | eu-central-1 | Amazon EC2 | bootstrap node groups, 3 per cluster | m7g.large, Linux, shared tenancy | 18 | 730 | instance-hour | 0.0978 | 1,285.09 | on-demand | 1,285.09 |
| EKS nodes | eu-central-1 | Amazon EC2 | payments pool, 5 cells (router 3, drainer 3, scheduler 5 pods) | m7g.2xlarge, Linux, Spot | 5 | 730 | instance-hour | 0.391 | 1,427.15 | Spot at 40% of on-demand | 570.86 |
| EKS nodes | eu-central-1 | Amazon EC2 | workers pool, platform add-ons | m7g.xlarge, Linux, shared tenancy | 6 | 730 | instance-hour | 0.1955 | 856.29 | on-demand | 856.29 |
| EKS nodes | eu-central-1 | Amazon EC2 | cde pool, locker (3 pods) | m7g.xlarge, Linux, shared tenancy | 1 | 730 | instance-hour | 0.1955 | 142.72 | on-demand | 142.72 |
| EKS nodes | eu-central-1 | Amazon EC2 | analytics stateful pool, ClickHouse 1 replica | r7g.xlarge, Linux, Spot | 1 | 730 | instance-hour | 0.2584 | 188.63 | Spot at 40% of on-demand | 75.45 |
| EKS nodes | eu-central-1 | Amazon EBS | ClickHouse data volume | gp3, 1 x 100 GB | 100 |  | GB-month | 0.0952 | 9.52 | on-demand | 9.52 |
| EKS nodes | eu-central-1 | Amazon EBS | node volumes (4 GiB OS + 80 GiB data) | gp3, 31 nodes x 84 GB | 2,604 |  | GB-month | 0.0952 | 247.90 | on-demand | 247.90 |
| Analytics | eu-central-1 | Amazon MSK | brokers | kafka.m7g.large, 3 AZ | 3 | 730 | broker-hour | 0.2445 | 535.46 | on-demand | 535.46 |
| Analytics | eu-central-1 | Amazon MSK | broker storage | 3 x 100 GB | 300 |  | GB-month | 0.119 | 35.70 | on-demand | 35.70 |
| Analytics | eu-central-1 | Amazon OpenSearch Service | data node | m7g.medium.search, 1 AZ | 1 | 730 | instance-hour | 0.081 | 59.13 | on-demand | 59.13 |
| Analytics | eu-central-1 | Amazon OpenSearch Service | data node storage | gp3, 20 GB | 20 |  | GB-month | 0.1452 | 2.90 | on-demand | 2.90 |
| Network | eu-central-1 | Amazon VPC | interface endpoints, workload VPC | 9 services x 3 AZ | 27 | 730 | endpoint-hour | 0.012 | 236.52 | on-demand | 236.52 |
| Network | us-east-1 | Amazon VPC | interface endpoints, workload VPC | 9 services x 3 AZ | 27 | 730 | endpoint-hour | 0.01 | 197.10 | on-demand | 197.10 |
| Network | us-east-2 | Amazon VPC | interface endpoints, workload VPC | 9 services x 3 AZ | 27 | 730 | endpoint-hour | 0.01 | 197.10 | on-demand | 197.10 |
| Network | eu-central-1 | Amazon VPC | interface endpoint data processed | AWS API traffic kept off NAT | 200 |  | GB | 0.01 | 2.00 | on-demand | 2.00 |
| Network | eu-central-1 | AWS Network Firewall | firewall endpoints, egress VPC | 3 AZ | 3 | 730 | endpoint-hour | 0.395 | 865.05 | on-demand | 865.05 |
| Network | eu-central-1 | Amazon VPC | NAT gateways behind the firewall | 3 AZ; hours and GB waived by the firewall endpoints | 3 | 730 | gateway-hour | 0 | 0.00 | on-demand | 0.00 |
| Network | eu-central-1 | Amazon VPC | public IPv4 of the NAT gateways | 3 addresses | 3 | 730 | address-hour | 0.005 | 10.95 | on-demand | 10.95 |
| Network | eu-central-1 | AWS Transit Gateway | VPC attachments, workload and egress | 2 attachments | 2 | 730 | attachment-hour | 0.06 | 87.60 | on-demand | 87.60 |
| Network | eu-central-1 | AWS Network Firewall | traffic processed | PSP calls and outgoing webhooks | 50 |  | GB | 0.065 | 3.25 | on-demand | 3.25 |
| Network | eu-central-1 | AWS Transit Gateway | data processed | egress traffic through two attachments | 100 |  | GB | 0.02 | 2.00 | on-demand | 2.00 |
| Network | global | AWS Global Accelerator | accelerator | fixed fee | 1 | 730 | accelerator-hour | 0.025 | 18.25 | on-demand | 18.25 |
| Network | global | AWS Global Accelerator | DT-Premium, Europe to Europe | API responses | 50 |  | GB | 0.015 | 0.75 | on-demand | 0.75 |
| Network | eu-central-1 | Elastic Load Balancing | NLB of the payments gateway | one per region with cells | 1 | 730 | LB-hour | 0.027 | 19.71 | on-demand | 19.71 |
| Network | eu-central-1 | Elastic Load Balancing | NLB capacity units | average LCU | 1 | 730 | LCU-hour | 0.006 | 4.38 | on-demand | 4.38 |
| Data transfer | eu-central-1 | AWS Data Transfer | out to the internet | PSP requests and API responses, 100 GB, tiered | 1 |  | month | 9 | 9.00 | on-demand | 9.00 |
| Data transfer | eu-central-1 | AWS Data Transfer | cross-AZ | router to MemoryDB and RDS Proxy, producers to MSK | 200 |  | GB | 0.02 | 4.00 | on-demand | 4.00 |
| Edge | us-east-1 | Amazon CloudFront | panel distribution, data out | PriceClass_100, Europe | 5 |  | GB | 0.085 | 0.43 | on-demand | 0.43 |
| Edge | us-east-1 | Amazon CloudFront | panel HTTPS requests | Europe | 500,000 |  | request | 1.2e-06 | 0.60 | on-demand | 0.60 |
| Edge | us-east-1 | AWS WAF | web ACL | panel | 1 |  | ACL-month | 5 | 5.00 | on-demand | 5.00 |
| Edge | us-east-1 | AWS WAF | rules | managed groups and rate rules | 10 |  | rule-month | 1 | 10.00 | on-demand | 10.00 |
| Edge | us-east-1 | AWS WAF | requests | panel | 500,000 |  | request | 6e-07 | 0.30 | on-demand | 0.30 |
| Edge | global | Amazon Route 53 | hosted zone | public zone of the environment | 1 |  | zone-month | 0.5 | 0.50 | on-demand | 0.50 |
| Data services | eu-central-1 | Amazon DynamoDB | merchant-cell map reads | on-demand | 1,000,000 |  | read request unit | 1.525e-07 | 0.15 | on-demand | 0.15 |
| Data services | eu-central-1 | Amazon DynamoDB | merchant-cell map writes and replicated writes | on-demand | 10,000 |  | write request unit | 7.625e-07 | 0.01 | on-demand | 0.01 |
| Backup and S3 | eu-central-1 | Amazon S3 | backup and event archive, Standard (days 0-7) | backups/, exports/, events/ | 20 |  | GB-month | 0.0245 | 0.49 | on-demand | 0.49 |
| Backup and S3 | eu-central-1 | Amazon S3 | Glacier Instant Retrieval (days 7-14) | D5 | 20 |  | GB-month | 0.005 | 0.10 | on-demand | 0.10 |
| Backup and S3 | eu-central-1 | Amazon S3 | Glacier Flexible Retrieval (days 14-35) | D5 | 60 |  | GB-month | 0.00405 | 0.24 | on-demand | 0.24 |
| Backup and S3 | eu-central-1 | Amazon S3 | monthly 7-year archive, Deep Archive | first-year average | 50 |  | GB-month | 0.0018 | 0.09 | on-demand | 0.09 |
| Backup and S3 | eu-central-1 | AWS Backup | Aurora snapshots in the vault | 35 days | 150 |  | GB-month | 0.023 | 3.45 | on-demand | 3.45 |
| Logs and security | eu-central-1 | Amazon CloudWatch | EKS control plane logs ingested | 5 log types, 6 clusters | 60 |  | GB | 0.63 | 37.80 | on-demand | 37.80 |
| Logs and security | eu-central-1 | Amazon CloudWatch | log storage | 30-day retention, steady state | 60 |  | GB-month | 0.0324 | 1.94 | on-demand | 1.94 |
| Logs and security | eu-central-1 | Amazon CloudWatch | VPC flow logs and firewall logs to S3 | vended log delivery | 50 |  | GB | 0.285 | 14.25 | on-demand | 14.25 |
| Logs and security | eu-central-1 | AWS KMS | customer managed keys | 10 per region with replicas, plus service keys | 40 |  | key-month | 1 | 40.00 | on-demand | 40.00 |
| Logs and security | eu-central-1 | AWS KMS | requests |  | 2,000,000 |  | request | 3e-06 | 6.00 | on-demand | 6.00 |
| Logs and security | eu-central-1 | AWS Secrets Manager | secrets | with replicas | 40 |  | secret-month | 0.4 | 16.00 | on-demand | 16.00 |
| Logs and security | eu-central-1 | Amazon GuardDuty | RDS protection | Aurora vCPU | 12 |  | vCPU-month | 1.23 | 14.76 | on-demand | 14.76 |
| Logs and security | eu-central-1 | Amazon GuardDuty | EKS runtime monitoring | 108 node vCPU, tiered | 1 |  | month | 207.36 | 207.36 | on-demand | 207.36 |
| Logs and security | eu-central-1 | Amazon GuardDuty | CloudTrail, VPC flow and DNS analysis | foundational | 30 |  | GB | 1.15 | 34.50 | on-demand | 34.50 |
| Logs and security | eu-central-1 | AWS Security Hub | security checks | 3 regions | 50,000 |  | check | 0.001 | 50.00 | on-demand | 50.00 |
| Logs and security | eu-central-1 | AWS Config | configuration items | node and ENI churn | 20,000 |  | item | 0.003 | 60.00 | on-demand | 60.00 |
| Logs and security | eu-central-1 | AWS Config | conformance pack evaluations |  | 50,000 |  | evaluation | 0.001 | 50.00 | on-demand | 50.00 |
| Logs and security | eu-central-1 | Amazon Inspector | EC2 scanning | nodes | 31 | 730 | instance-hour | 0.0021 | 47.52 | on-demand | 47.52 |
| **Total** | | | | | | | | | **10,228.52** | | **9,259.05** |
