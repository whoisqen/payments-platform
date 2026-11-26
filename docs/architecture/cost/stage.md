# Cost of stage

Monthly cost at the target load, from the AWS Price List (eu-central-1, us-east-1, us-east-2, global). Method and assumptions: [README.md](README.md).

- Sizing: `config/environments/stage.yaml` changes only `eks.spot_pools`; everything else is the prod size of `config/environments/prod.yaml`.
- Stage therefore runs the full prod topology: 4 cells and the spare at prod classes, the us-east-1 standby (EKS, MemoryDB, Aurora readers) and the us-east-2 secondaries.
- Payments and stateful node pools run on Spot; managed data stores run on demand.
- Traffic lines use test volumes, not the prod load.
- Every line runs 730 hours: the repository has no schedule for stage.
- Commitments: none (non-prod is not reserved); the committed column applies the Spot planning rate only.

Total: **148,093 USD/month on demand**, **137,441 USD/month committed**.

## By group

| Group | On-demand (USD/month) | Committed (USD/month) |
|---|---:|---:|
| Aurora | 78,950.74 | 78,950.74 |
| MemoryDB | 29,780.20 | 29,780.20 |
| EKS nodes | 24,130.46 | 13,478.60 |
| Analytics | 8,896.57 | 8,896.57 |
| Logs and security | 2,688.27 | 2,688.27 |
| Network | 2,639.85 | 2,639.85 |
| EKS | 803.00 | 803.00 |
| Backup and S3 | 100.60 | 100.60 |
| Data transfer | 84.00 | 84.00 |
| Edge | 18.15 | 18.15 |
| Data services | 0.78 | 0.78 |
| **Total** | **148,092.62** | **137,440.76** |

## Line items

Hours are per month (730 for 24/7). Usage lines have no hours: quantity times unit price.

| Group | Region | Service | Resource | Configuration | Quantity | Hours | Unit | Unit price (USD) | Monthly on-demand (USD) | Pricing model | Monthly committed (USD) |
|---|---|---|---|---|---:|---:|---|---:|---:|---|---:|
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-cell-0 writer | db.r7g.12xlarge, I/O-Optimized | 1 | 730 | instance-hour | 10.381 | 7,578.13 | on-demand | 7,578.13 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-cell-0 reader | db.r7g.4xlarge, I/O-Optimized | 1 | 730 | instance-hour | 3.461 | 2,526.53 | on-demand | 2,526.53 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-cell-0 storage | I/O-Optimized storage | 200 |  | GB-month | 0.268 | 53.60 | on-demand | 53.60 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-cell-1 writer | db.r7g.12xlarge, I/O-Optimized | 1 | 730 | instance-hour | 10.381 | 7,578.13 | on-demand | 7,578.13 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-cell-1 reader | db.r7g.4xlarge, I/O-Optimized | 1 | 730 | instance-hour | 3.461 | 2,526.53 | on-demand | 2,526.53 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-cell-1 storage | I/O-Optimized storage | 200 |  | GB-month | 0.268 | 53.60 | on-demand | 53.60 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-cell-2 writer | db.r7g.12xlarge, I/O-Optimized | 1 | 730 | instance-hour | 10.381 | 7,578.13 | on-demand | 7,578.13 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-cell-2 reader | db.r7g.4xlarge, I/O-Optimized | 1 | 730 | instance-hour | 3.461 | 2,526.53 | on-demand | 2,526.53 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-cell-2 storage | I/O-Optimized storage | 200 |  | GB-month | 0.268 | 53.60 | on-demand | 53.60 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-cell-3 writer | db.r7g.12xlarge, I/O-Optimized | 1 | 730 | instance-hour | 10.381 | 7,578.13 | on-demand | 7,578.13 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-cell-3 reader | db.r7g.4xlarge, I/O-Optimized | 1 | 730 | instance-hour | 3.461 | 2,526.53 | on-demand | 2,526.53 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-cell-3 storage | I/O-Optimized storage | 200 |  | GB-month | 0.268 | 53.60 | on-demand | 53.60 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-spare writer | db.r7g.12xlarge, I/O-Optimized | 1 | 730 | instance-hour | 10.381 | 7,578.13 | on-demand | 7,578.13 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-spare reader | db.r7g.4xlarge, I/O-Optimized | 1 | 730 | instance-hour | 3.461 | 2,526.53 | on-demand | 2,526.53 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-spare storage | I/O-Optimized storage | 50 |  | GB-month | 0.268 | 13.40 | on-demand | 13.40 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-locker writer | db.r7g.12xlarge, I/O-Optimized | 1 | 730 | instance-hour | 10.381 | 7,578.13 | on-demand | 7,578.13 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-locker reader | db.r7g.4xlarge, I/O-Optimized | 1 | 730 | instance-hour | 3.461 | 2,526.53 | on-demand | 2,526.53 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-locker storage | I/O-Optimized storage | 50 |  | GB-month | 0.268 | 13.40 | on-demand | 13.40 |
| Aurora | eu-central-1 | Amazon RDS Proxy | proxies of 6 clusters | billed per vCPU of the cluster instances | 384 | 730 | vCPU-hour | 0.018 | 5,045.76 | on-demand | 5,045.76 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | backup storage above the free allowance | 35-day PITR | 900 |  | GB-month | 0.023 | 20.70 | on-demand | 20.70 |
| Aurora | us-east-1 | Amazon Aurora PostgreSQL | aurora-cell-0 secondary reader | db.r7g.4xlarge, I/O-Optimized | 1 | 730 | instance-hour | 2.874 | 2,098.02 | on-demand | 2,098.02 |
| Aurora | us-east-1 | Amazon Aurora PostgreSQL | aurora-cell-1 secondary reader | db.r7g.4xlarge, I/O-Optimized | 1 | 730 | instance-hour | 2.874 | 2,098.02 | on-demand | 2,098.02 |
| Aurora | us-east-1 | Amazon Aurora PostgreSQL | aurora-cell-2 secondary reader | db.r7g.4xlarge, I/O-Optimized | 1 | 730 | instance-hour | 2.874 | 2,098.02 | on-demand | 2,098.02 |
| Aurora | us-east-1 | Amazon Aurora PostgreSQL | aurora-cell-3 secondary reader | db.r7g.4xlarge, I/O-Optimized | 1 | 730 | instance-hour | 2.874 | 2,098.02 | on-demand | 2,098.02 |
| Aurora | us-east-1 | Amazon Aurora PostgreSQL | aurora-spare secondary reader | db.r7g.4xlarge, I/O-Optimized | 1 | 730 | instance-hour | 2.874 | 2,098.02 | on-demand | 2,098.02 |
| Aurora | us-east-1 | Amazon Aurora PostgreSQL | aurora-locker secondary reader | db.r7g.4xlarge, I/O-Optimized | 1 | 730 | instance-hour | 2.874 | 2,098.02 | on-demand | 2,098.02 |
| Aurora | us-east-1 | Amazon Aurora PostgreSQL | global secondaries storage, 6 clusters | I/O-Optimized storage | 900 |  | GB-month | 0.225 | 202.50 | on-demand | 202.50 |
| Aurora | us-east-1 | Amazon Aurora PostgreSQL | replicated write I/O into this region | Aurora Global Database | 50,000,000 |  | I/O | 2.2e-07 | 11.00 | on-demand | 11.00 |
| Data transfer | eu-central-1 | AWS Data Transfer | Aurora global replication to us-east-1 | inter-region | 200 |  | GB | 0.02 | 4.00 | on-demand | 4.00 |
| Aurora | us-east-2 | Amazon Aurora PostgreSQL | global secondaries storage, 6 clusters | I/O-Optimized storage | 900 |  | GB-month | 0.225 | 202.50 | on-demand | 202.50 |
| Aurora | us-east-2 | Amazon Aurora PostgreSQL | replicated write I/O into this region | Aurora Global Database | 50,000,000 |  | I/O | 2.2e-07 | 11.00 | on-demand | 11.00 |
| Data transfer | eu-central-1 | AWS Data Transfer | Aurora global replication to us-east-2 | inter-region | 200 |  | GB | 0.02 | 4.00 | on-demand | 4.00 |
| MemoryDB | eu-central-1 | Amazon MemoryDB | memorydb-cell-0 | db.r7g.xlarge, 2 shard(s) x 3 nodes | 6 | 730 | node-hour | 0.741 | 3,245.58 | on-demand | 3,245.58 |
| MemoryDB | eu-central-1 | Amazon MemoryDB | memorydb-cell-1 | db.r7g.xlarge, 2 shard(s) x 3 nodes | 6 | 730 | node-hour | 0.741 | 3,245.58 | on-demand | 3,245.58 |
| MemoryDB | eu-central-1 | Amazon MemoryDB | memorydb-cell-2 | db.r7g.xlarge, 2 shard(s) x 3 nodes | 6 | 730 | node-hour | 0.741 | 3,245.58 | on-demand | 3,245.58 |
| MemoryDB | eu-central-1 | Amazon MemoryDB | memorydb-cell-3 | db.r7g.xlarge, 2 shard(s) x 3 nodes | 6 | 730 | node-hour | 0.741 | 3,245.58 | on-demand | 3,245.58 |
| MemoryDB | eu-central-1 | Amazon MemoryDB | memorydb-spare | db.r7g.xlarge, 2 shard(s) x 3 nodes | 6 | 730 | node-hour | 0.741 | 3,245.58 | on-demand | 3,245.58 |
| MemoryDB | us-east-1 | Amazon MemoryDB | memorydb-cell-0 standby | db.r7g.xlarge, 2 shard(s) x 3 nodes | 6 | 730 | node-hour | 0.617 | 2,702.46 | on-demand | 2,702.46 |
| MemoryDB | us-east-1 | Amazon MemoryDB | memorydb-cell-1 standby | db.r7g.xlarge, 2 shard(s) x 3 nodes | 6 | 730 | node-hour | 0.617 | 2,702.46 | on-demand | 2,702.46 |
| MemoryDB | us-east-1 | Amazon MemoryDB | memorydb-cell-2 standby | db.r7g.xlarge, 2 shard(s) x 3 nodes | 6 | 730 | node-hour | 0.617 | 2,702.46 | on-demand | 2,702.46 |
| MemoryDB | us-east-1 | Amazon MemoryDB | memorydb-cell-3 standby | db.r7g.xlarge, 2 shard(s) x 3 nodes | 6 | 730 | node-hour | 0.617 | 2,702.46 | on-demand | 2,702.46 |
| MemoryDB | us-east-1 | Amazon MemoryDB | memorydb-spare standby | db.r7g.xlarge, 2 shard(s) x 3 nodes | 6 | 730 | node-hour | 0.617 | 2,702.46 | on-demand | 2,702.46 |
| MemoryDB | eu-central-1 | Amazon MemoryDB | data written | all cells | 200 |  | GB | 0.2 | 40.00 | on-demand | 40.00 |
| EKS | eu-central-1 | Amazon EKS | control planes | 4 cells, spare, analytics | 6 | 730 | cluster-hour | 0.1 | 438.00 | on-demand | 438.00 |
| EKS | us-east-1 | Amazon EKS | control planes, standby | 4 cells, spare | 5 | 730 | cluster-hour | 0.1 | 365.00 | on-demand | 365.00 |
| EKS nodes | eu-central-1 | Amazon EC2 | bootstrap node groups, 3 per cluster | m7g.large, Linux, shared tenancy | 18 | 730 | instance-hour | 0.0978 | 1,285.09 | on-demand | 1,285.09 |
| EKS nodes | eu-central-1 | Amazon EC2 | payments pool, 4 working cells (router min 20, drainer 3, scheduler 5) | m7g.4xlarge, Linux, Spot | 12 | 730 | instance-hour | 0.7821 | 6,851.20 | Spot at 40% of on-demand | 2,740.48 |
| EKS nodes | eu-central-1 | Amazon EC2 | payments pool, spare cell (same minimum replicas) | m7g.4xlarge, Linux, Spot | 3 | 730 | instance-hour | 0.7821 | 1,712.80 | Spot at 40% of on-demand | 685.12 |
| EKS nodes | eu-central-1 | Amazon EC2 | workers pool, platform add-ons of 5 cell clusters | m7g.2xlarge, Linux, shared tenancy | 5 | 730 | instance-hour | 0.391 | 1,427.15 | on-demand | 1,427.15 |
| EKS nodes | eu-central-1 | Amazon EC2 | cde pool, locker (min 5 pods) | m7g.xlarge, Linux, shared tenancy | 3 | 730 | instance-hour | 0.1955 | 428.15 | on-demand | 428.15 |
| EKS nodes | eu-central-1 | Amazon EC2 | analytics stateful pool, ClickHouse 4 shards x 2 replicas | r7g.2xlarge, Linux, Spot | 8 | 730 | instance-hour | 0.5168 | 3,018.11 | Spot at 40% of on-demand | 1,207.24 |
| EKS nodes | eu-central-1 | Amazon EC2 | analytics stateful pool, ClickHouse Keeper | m7g.large, Linux, Spot | 3 | 730 | instance-hour | 0.0978 | 214.18 | Spot at 40% of on-demand | 85.67 |
| EKS nodes | eu-central-1 | Amazon EC2 | analytics workers pool | m7g.2xlarge, Linux, shared tenancy | 2 | 730 | instance-hour | 0.391 | 570.86 | on-demand | 570.86 |
| EKS nodes | us-east-1 | Amazon EC2 | bootstrap node groups, standby | m7g.large, Linux, shared tenancy | 15 | 730 | instance-hour | 0.0816 | 893.52 | on-demand | 893.52 |
| EKS nodes | us-east-1 | Amazon EC2 | payments pool, 5 standby clusters (40 vCPU cap each) | m7g.4xlarge, Linux, Spot | 10 | 730 | instance-hour | 0.6528 | 4,765.44 | Spot at 40% of on-demand | 1,906.18 |
| EKS nodes | us-east-1 | Amazon EC2 | payments pool, 5 standby clusters (remainder of the cap) | m7g.2xlarge, Linux, Spot | 5 | 730 | instance-hour | 0.3264 | 1,191.36 | Spot at 40% of on-demand | 476.54 |
| EKS nodes | us-east-1 | Amazon EC2 | cde pool, standby locker | m7g.xlarge, Linux, shared tenancy | 3 | 730 | instance-hour | 0.1632 | 357.41 | on-demand | 357.41 |
| EKS nodes | eu-central-1 | Amazon EBS | ClickHouse data volumes | gp3, 8 x 1,000 GB | 8,000 |  | GB-month | 0.0952 | 761.60 | on-demand | 761.60 |
| EKS nodes | eu-central-1 | Amazon EBS | node volumes (4 GiB OS + 80 GiB data) | gp3, 54 nodes x 84 GB | 4,536 |  | GB-month | 0.0952 | 431.83 | on-demand | 431.83 |
| EKS nodes | us-east-1 | Amazon EBS | node volumes (4 GiB OS + 80 GiB data) | gp3, 33 nodes x 84 GB | 2,772 |  | GB-month | 0.08 | 221.76 | on-demand | 221.76 |
| Analytics | eu-central-1 | Amazon MSK | brokers | kafka.m7g.xlarge, 3 AZ | 9 | 730 | broker-hour | 0.4888 | 3,211.42 | on-demand | 3,211.42 |
| Analytics | eu-central-1 | Amazon MSK | broker storage | 9 x 2,000 GB | 18,000 |  | GB-month | 0.119 | 2,142.00 | on-demand | 2,142.00 |
| Analytics | eu-central-1 | Amazon OpenSearch Service | data nodes | r7g.xlarge.search, 3 AZ | 6 | 730 | instance-hour | 0.429 | 1,879.02 | on-demand | 1,879.02 |
| Analytics | eu-central-1 | Amazon OpenSearch Service | dedicated masters | m7g.large.search | 3 | 730 | instance-hour | 0.162 | 354.78 | on-demand | 354.78 |
| Analytics | eu-central-1 | Amazon OpenSearch Service | UltraWarm nodes | ultrawarm1.medium.search | 2 | 730 | instance-hour | 0.284 | 414.64 | on-demand | 414.64 |
| Analytics | eu-central-1 | Amazon OpenSearch Service | data node storage | gp3, 6 x 1,024 GB | 6,144 |  | GB-month | 0.1452 | 892.11 | on-demand | 892.11 |
| Analytics | eu-central-1 | Amazon OpenSearch Service | UltraWarm managed storage | indices older than 30 days | 100 |  | GB-month | 0.026 | 2.60 | on-demand | 2.60 |
| Network | eu-central-1 | Amazon VPC | interface endpoints, workload VPC | 9 services x 3 AZ | 27 | 730 | endpoint-hour | 0.012 | 236.52 | on-demand | 236.52 |
| Network | us-east-1 | Amazon VPC | interface endpoints, workload VPC | 9 services x 3 AZ | 27 | 730 | endpoint-hour | 0.01 | 197.10 | on-demand | 197.10 |
| Network | us-east-2 | Amazon VPC | interface endpoints, workload VPC | 9 services x 3 AZ | 27 | 730 | endpoint-hour | 0.01 | 197.10 | on-demand | 197.10 |
| Network | eu-central-1 | Amazon VPC | interface endpoint data processed | AWS API traffic kept off NAT | 500 |  | GB | 0.01 | 5.00 | on-demand | 5.00 |
| Network | eu-central-1 | AWS Network Firewall | firewall endpoints, egress VPC | 3 AZ | 3 | 730 | endpoint-hour | 0.395 | 865.05 | on-demand | 865.05 |
| Network | eu-central-1 | Amazon VPC | NAT gateways behind the firewall | 3 AZ; hours and GB waived by the firewall endpoints | 3 | 730 | gateway-hour | 0 | 0.00 | on-demand | 0.00 |
| Network | eu-central-1 | Amazon VPC | public IPv4 of the NAT gateways | 3 addresses | 3 | 730 | address-hour | 0.005 | 10.95 | on-demand | 10.95 |
| Network | eu-central-1 | AWS Transit Gateway | VPC attachments, workload and egress | 2 attachments | 2 | 730 | attachment-hour | 0.06 | 87.60 | on-demand | 87.60 |
| Network | us-east-1 | AWS Network Firewall | firewall endpoints, egress VPC | 3 AZ | 3 | 730 | endpoint-hour | 0.395 | 865.05 | on-demand | 865.05 |
| Network | us-east-1 | Amazon VPC | NAT gateways behind the firewall | 3 AZ; hours and GB waived by the firewall endpoints | 3 | 730 | gateway-hour | 0 | 0.00 | on-demand | 0.00 |
| Network | us-east-1 | Amazon VPC | public IPv4 of the NAT gateways | 3 addresses | 3 | 730 | address-hour | 0.005 | 10.95 | on-demand | 10.95 |
| Network | us-east-1 | AWS Transit Gateway | VPC attachments, workload and egress | 2 attachments | 2 | 730 | attachment-hour | 0.05 | 73.00 | on-demand | 73.00 |
| Network | eu-central-1 | AWS Network Firewall | traffic processed | PSP calls and outgoing webhooks | 200 |  | GB | 0.065 | 13.00 | on-demand | 13.00 |
| Network | eu-central-1 | AWS Transit Gateway | data processed | egress traffic through two attachments | 400 |  | GB | 0.02 | 8.00 | on-demand | 8.00 |
| Network | global | AWS Global Accelerator | accelerator | fixed fee | 1 | 730 | accelerator-hour | 0.025 | 18.25 | on-demand | 18.25 |
| Network | global | AWS Global Accelerator | DT-Premium, Europe to Europe | API responses | 200 |  | GB | 0.015 | 3.00 | on-demand | 3.00 |
| Network | eu-central-1 | Elastic Load Balancing | NLB of the payments gateway | one per region with cells | 1 | 730 | LB-hour | 0.027 | 19.71 | on-demand | 19.71 |
| Network | eu-central-1 | Elastic Load Balancing | NLB capacity units | average LCU | 2 | 730 | LCU-hour | 0.006 | 8.76 | on-demand | 8.76 |
| Network | us-east-1 | Elastic Load Balancing | NLB of the payments gateway | one per region with cells | 1 | 730 | LB-hour | 0.0225 | 16.43 | on-demand | 16.43 |
| Network | us-east-1 | Elastic Load Balancing | NLB capacity units | average LCU | 1 | 730 | LCU-hour | 0.006 | 4.38 | on-demand | 4.38 |
| Data transfer | eu-central-1 | AWS Data Transfer | out to the internet | PSP requests and API responses, 400 GB, tiered | 1 |  | month | 36 | 36.00 | on-demand | 36.00 |
| Data transfer | eu-central-1 | AWS Data Transfer | cross-AZ | router to MemoryDB and RDS Proxy, producers to MSK | 1,000 |  | GB | 0.02 | 20.00 | on-demand | 20.00 |
| Edge | us-east-1 | Amazon CloudFront | panel distribution, data out | PriceClass_100, Europe | 10 |  | GB | 0.085 | 0.85 | on-demand | 0.85 |
| Edge | us-east-1 | Amazon CloudFront | panel HTTPS requests | Europe | 1,000,000 |  | request | 1.2e-06 | 1.20 | on-demand | 1.20 |
| Edge | us-east-1 | AWS WAF | web ACL | panel | 1 |  | ACL-month | 5 | 5.00 | on-demand | 5.00 |
| Edge | us-east-1 | AWS WAF | rules | managed groups and rate rules | 10 |  | rule-month | 1 | 10.00 | on-demand | 10.00 |
| Edge | us-east-1 | AWS WAF | requests | panel | 1,000,000 |  | request | 6e-07 | 0.60 | on-demand | 0.60 |
| Edge | global | Amazon Route 53 | hosted zone | public zone of the environment | 1 |  | zone-month | 0.5 | 0.50 | on-demand | 0.50 |
| Data services | eu-central-1 | Amazon DynamoDB | merchant-cell map reads | on-demand | 5,000,000 |  | read request unit | 1.525e-07 | 0.76 | on-demand | 0.76 |
| Data services | eu-central-1 | Amazon DynamoDB | merchant-cell map writes and replicated writes | on-demand | 30,000 |  | write request unit | 7.625e-07 | 0.02 | on-demand | 0.02 |
| Backup and S3 | eu-central-1 | Amazon S3 | backup and event archive, Standard (days 0-7) | backups/, exports/, events/ | 100 |  | GB-month | 0.0245 | 2.45 | on-demand | 2.45 |
| Backup and S3 | eu-central-1 | Amazon S3 | Glacier Instant Retrieval (days 7-14) | D5 | 100 |  | GB-month | 0.005 | 0.50 | on-demand | 0.50 |
| Backup and S3 | eu-central-1 | Amazon S3 | Glacier Flexible Retrieval (days 14-35) | D5 | 300 |  | GB-month | 0.00405 | 1.21 | on-demand | 1.21 |
| Backup and S3 | eu-central-1 | Amazon S3 | monthly 7-year archive, Deep Archive | first-year average | 300 |  | GB-month | 0.0018 | 0.54 | on-demand | 0.54 |
| Backup and S3 | eu-central-1 | Amazon S3 | Replication Time Control to 2 regions | new objects x 2 | 600 |  | GB | 0.015 | 9.00 | on-demand | 9.00 |
| Data transfer | eu-central-1 | AWS Data Transfer | S3 replication to the recovery regions | inter-region | 600 |  | GB | 0.02 | 12.00 | on-demand | 12.00 |
| Backup and S3 | us-east-1 | Amazon S3 | locked replica bucket, Glacier IR | 35 days | 300 |  | GB-month | 0.004 | 1.20 | on-demand | 1.20 |
| Backup and S3 | us-east-2 | Amazon S3 | locked replica bucket, Glacier IR | 35 days | 300 |  | GB-month | 0.004 | 1.20 | on-demand | 1.20 |
| Backup and S3 | eu-central-1 | AWS Backup | Aurora snapshots in the vault | 35 days | 1,300 |  | GB-month | 0.023 | 29.90 | on-demand | 29.90 |
| Backup and S3 | us-east-1 | AWS Backup | Aurora snapshots in the vault | 35 days | 1,300 |  | GB-month | 0.021 | 27.30 | on-demand | 27.30 |
| Backup and S3 | us-east-2 | AWS Backup | Aurora snapshots in the vault | 35 days | 1,300 |  | GB-month | 0.021 | 27.30 | on-demand | 27.30 |
| Data transfer | eu-central-1 | AWS Data Transfer | backup copies to us-east-1 and us-east-2 | inter-region | 400 |  | GB | 0.02 | 8.00 | on-demand | 8.00 |
| Logs and security | eu-central-1 | Amazon CloudWatch | EKS control plane logs ingested | 5 log types, 11 clusters | 330 |  | GB | 0.63 | 207.90 | on-demand | 207.90 |
| Logs and security | eu-central-1 | Amazon CloudWatch | log storage | 365-day retention, steady state | 4,015 |  | GB-month | 0.0324 | 130.09 | on-demand | 130.09 |
| Logs and security | eu-central-1 | Amazon CloudWatch | VPC flow logs and firewall logs to S3 | vended log delivery | 150 |  | GB | 0.285 | 42.75 | on-demand | 42.75 |
| Logs and security | eu-central-1 | AWS KMS | customer managed keys | 10 per region with replicas, plus service keys | 40 |  | key-month | 1 | 40.00 | on-demand | 40.00 |
| Logs and security | eu-central-1 | AWS KMS | requests |  | 5,000,000 |  | request | 3e-06 | 15.00 | on-demand | 15.00 |
| Logs and security | eu-central-1 | AWS Secrets Manager | secrets | with replicas | 60 |  | secret-month | 0.4 | 24.00 | on-demand | 24.00 |
| Logs and security | eu-central-1 | Amazon GuardDuty | RDS protection | Aurora vCPU | 480 |  | vCPU-month | 1.23 | 590.40 | on-demand | 590.40 |
| Logs and security | eu-central-1 | Amazon GuardDuty | EKS runtime monitoring | 656 node vCPU, tiered | 1 |  | month | 1109.76 | 1,109.76 | on-demand | 1,109.76 |
| Logs and security | eu-central-1 | Amazon GuardDuty | CloudTrail, VPC flow and DNS analysis | foundational | 100 |  | GB | 1.15 | 115.00 | on-demand | 115.00 |
| Logs and security | eu-central-1 | AWS Security Hub | security checks | 3 regions | 60,000 |  | check | 0.001 | 60.00 | on-demand | 60.00 |
| Logs and security | eu-central-1 | AWS Config | configuration items | node and ENI churn | 40,000 |  | item | 0.003 | 120.00 | on-demand | 120.00 |
| Logs and security | eu-central-1 | AWS Config | conformance pack evaluations |  | 100,000 |  | evaluation | 0.001 | 100.00 | on-demand | 100.00 |
| Logs and security | eu-central-1 | Amazon Inspector | EC2 scanning | nodes | 87 | 730 | instance-hour | 0.0021 | 133.37 | on-demand | 133.37 |
| **Total** | | | | | | | | | **148,092.62** | | **137,440.76** |
