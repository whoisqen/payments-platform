# Cost of prod

Monthly cost at the target load, from the AWS Price List (eu-central-1, us-east-1, us-east-2, global). Method and assumptions: [README.md](README.md).

- Sizing: `config/environments/prod.yaml`, stacks in `infra/live/prod/`, replicas from the chart defaults in `deploy/charts/*/values.yaml`.
- eu-central-1 runs 4 working cells, the spare and the locker, each Aurora cluster with a `db.r7g.12xlarge` writer and one `db.r7g.4xlarge` reader on I/O-Optimized storage behind RDS Proxy.
- us-east-1 holds the warm standby: an Aurora reader per secondary, MemoryDB and an EKS cluster per cell; us-east-2 holds headless secondaries.
- Compute is the target capacity: router at 60 RPS per pod, so the HPA floor of 20 pods per cell holds the daily peak of 480 TPS.
- Committed column: RDS and MemoryDB reserved 1 year no upfront, OpenSearch reserved 1 year no upfront, Compute Savings Plan 1 year no upfront on 80% of EC2.

Total: **161,487 USD/month on demand**, **129,881 USD/month committed**.

## By group

| Group | On-demand (USD/month) | Committed (USD/month) |
|---|---:|---:|
| Aurora | 85,316.44 | 68,476.36 |
| MemoryDB | 30,984.20 | 21,479.60 |
| EKS nodes | 24,130.46 | 19,560.83 |
| Analytics | 8,919.97 | 8,227.93 |
| Network | 3,885.39 | 3,885.39 |
| Logs and security | 3,516.50 | 3,516.50 |
| Data transfer | 2,736.00 | 2,736.00 |
| Backup and S3 | 1,158.77 | 1,158.77 |
| EKS | 803.00 | 803.00 |
| Edge | 28.75 | 28.75 |
| Data services | 7.85 | 7.85 |
| **Total** | **161,487.33** | **129,880.98** |

## Line items

Hours are per month (730 for 24/7). Usage lines have no hours: quantity times unit price.

| Group | Region | Service | Resource | Configuration | Quantity | Hours | Unit | Unit price (USD) | Monthly on-demand (USD) | Pricing model | Monthly committed (USD) |
|---|---|---|---|---|---:|---:|---|---:|---:|---|---:|
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-cell-0 writer | db.r7g.12xlarge, I/O-Optimized | 1 | 730 | instance-hour | 10.381 | 7,578.13 | RDS RI 1yr no upfront | 5,835.30 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-cell-0 reader | db.r7g.4xlarge, I/O-Optimized | 1 | 730 | instance-hour | 3.461 | 2,526.53 | RDS RI 1yr no upfront | 1,945.20 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-cell-0 storage | I/O-Optimized storage | 2,000 |  | GB-month | 0.268 | 536.00 | on-demand | 536.00 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-cell-1 writer | db.r7g.12xlarge, I/O-Optimized | 1 | 730 | instance-hour | 10.381 | 7,578.13 | RDS RI 1yr no upfront | 5,835.30 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-cell-1 reader | db.r7g.4xlarge, I/O-Optimized | 1 | 730 | instance-hour | 3.461 | 2,526.53 | RDS RI 1yr no upfront | 1,945.20 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-cell-1 storage | I/O-Optimized storage | 2,000 |  | GB-month | 0.268 | 536.00 | on-demand | 536.00 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-cell-2 writer | db.r7g.12xlarge, I/O-Optimized | 1 | 730 | instance-hour | 10.381 | 7,578.13 | RDS RI 1yr no upfront | 5,835.30 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-cell-2 reader | db.r7g.4xlarge, I/O-Optimized | 1 | 730 | instance-hour | 3.461 | 2,526.53 | RDS RI 1yr no upfront | 1,945.20 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-cell-2 storage | I/O-Optimized storage | 2,000 |  | GB-month | 0.268 | 536.00 | on-demand | 536.00 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-cell-3 writer | db.r7g.12xlarge, I/O-Optimized | 1 | 730 | instance-hour | 10.381 | 7,578.13 | RDS RI 1yr no upfront | 5,835.30 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-cell-3 reader | db.r7g.4xlarge, I/O-Optimized | 1 | 730 | instance-hour | 3.461 | 2,526.53 | RDS RI 1yr no upfront | 1,945.20 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-cell-3 storage | I/O-Optimized storage | 2,000 |  | GB-month | 0.268 | 536.00 | on-demand | 536.00 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-spare writer | db.r7g.12xlarge, I/O-Optimized | 1 | 730 | instance-hour | 10.381 | 7,578.13 | RDS RI 1yr no upfront | 5,835.30 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-spare reader | db.r7g.4xlarge, I/O-Optimized | 1 | 730 | instance-hour | 3.461 | 2,526.53 | RDS RI 1yr no upfront | 1,945.20 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-spare storage | I/O-Optimized storage | 100 |  | GB-month | 0.268 | 26.80 | on-demand | 26.80 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-locker writer | db.r7g.12xlarge, I/O-Optimized | 1 | 730 | instance-hour | 10.381 | 7,578.13 | RDS RI 1yr no upfront | 5,835.30 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-locker reader | db.r7g.4xlarge, I/O-Optimized | 1 | 730 | instance-hour | 3.461 | 2,526.53 | RDS RI 1yr no upfront | 1,945.20 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-locker storage | I/O-Optimized storage | 500 |  | GB-month | 0.268 | 134.00 | on-demand | 134.00 |
| Aurora | eu-central-1 | Amazon RDS Proxy | proxies of 6 clusters | billed per vCPU of the cluster instances | 384 | 730 | vCPU-hour | 0.018 | 5,045.76 | on-demand | 5,045.76 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | backup storage above the free allowance | 35-day PITR | 8,600 |  | GB-month | 0.023 | 197.80 | on-demand | 197.80 |
| Aurora | us-east-1 | Amazon Aurora PostgreSQL | aurora-cell-0 secondary reader | db.r7g.4xlarge, I/O-Optimized | 1 | 730 | instance-hour | 2.874 | 2,098.02 | RDS RI 1yr no upfront | 1,615.50 |
| Aurora | us-east-1 | Amazon Aurora PostgreSQL | aurora-cell-1 secondary reader | db.r7g.4xlarge, I/O-Optimized | 1 | 730 | instance-hour | 2.874 | 2,098.02 | RDS RI 1yr no upfront | 1,615.50 |
| Aurora | us-east-1 | Amazon Aurora PostgreSQL | aurora-cell-2 secondary reader | db.r7g.4xlarge, I/O-Optimized | 1 | 730 | instance-hour | 2.874 | 2,098.02 | RDS RI 1yr no upfront | 1,615.50 |
| Aurora | us-east-1 | Amazon Aurora PostgreSQL | aurora-cell-3 secondary reader | db.r7g.4xlarge, I/O-Optimized | 1 | 730 | instance-hour | 2.874 | 2,098.02 | RDS RI 1yr no upfront | 1,615.50 |
| Aurora | us-east-1 | Amazon Aurora PostgreSQL | aurora-spare secondary reader | db.r7g.4xlarge, I/O-Optimized | 1 | 730 | instance-hour | 2.874 | 2,098.02 | RDS RI 1yr no upfront | 1,615.50 |
| Aurora | us-east-1 | Amazon Aurora PostgreSQL | aurora-locker secondary reader | db.r7g.4xlarge, I/O-Optimized | 1 | 730 | instance-hour | 2.874 | 2,098.02 | RDS RI 1yr no upfront | 1,615.50 |
| Aurora | us-east-1 | Amazon Aurora PostgreSQL | global secondaries storage, 6 clusters | I/O-Optimized storage | 8,600 |  | GB-month | 0.225 | 1,935.00 | on-demand | 1,935.00 |
| Aurora | us-east-1 | Amazon Aurora PostgreSQL | replicated write I/O into this region | Aurora Global Database | 1,550,000,000 |  | I/O | 2.2e-07 | 341.00 | on-demand | 341.00 |
| Data transfer | eu-central-1 | AWS Data Transfer | Aurora global replication to us-east-1 | inter-region | 6,200 |  | GB | 0.02 | 124.00 | on-demand | 124.00 |
| Aurora | us-east-2 | Amazon Aurora PostgreSQL | global secondaries storage, 6 clusters | I/O-Optimized storage | 8,600 |  | GB-month | 0.225 | 1,935.00 | on-demand | 1,935.00 |
| Aurora | us-east-2 | Amazon Aurora PostgreSQL | replicated write I/O into this region | Aurora Global Database | 1,550,000,000 |  | I/O | 2.2e-07 | 341.00 | on-demand | 341.00 |
| Data transfer | eu-central-1 | AWS Data Transfer | Aurora global replication to us-east-2 | inter-region | 6,200 |  | GB | 0.02 | 124.00 | on-demand | 124.00 |
| MemoryDB | eu-central-1 | Amazon MemoryDB | memorydb-cell-0 | db.r7g.xlarge, 2 shard(s) x 3 nodes | 6 | 730 | node-hour | 0.741 | 3,245.58 | MemoryDB reserved node 1yr no upfront | 2,207.52 |
| MemoryDB | eu-central-1 | Amazon MemoryDB | memorydb-cell-1 | db.r7g.xlarge, 2 shard(s) x 3 nodes | 6 | 730 | node-hour | 0.741 | 3,245.58 | MemoryDB reserved node 1yr no upfront | 2,207.52 |
| MemoryDB | eu-central-1 | Amazon MemoryDB | memorydb-cell-2 | db.r7g.xlarge, 2 shard(s) x 3 nodes | 6 | 730 | node-hour | 0.741 | 3,245.58 | MemoryDB reserved node 1yr no upfront | 2,207.52 |
| MemoryDB | eu-central-1 | Amazon MemoryDB | memorydb-cell-3 | db.r7g.xlarge, 2 shard(s) x 3 nodes | 6 | 730 | node-hour | 0.741 | 3,245.58 | MemoryDB reserved node 1yr no upfront | 2,207.52 |
| MemoryDB | eu-central-1 | Amazon MemoryDB | memorydb-spare | db.r7g.xlarge, 2 shard(s) x 3 nodes | 6 | 730 | node-hour | 0.741 | 3,245.58 | MemoryDB reserved node 1yr no upfront | 2,207.52 |
| MemoryDB | us-east-1 | Amazon MemoryDB | memorydb-cell-0 standby | db.r7g.xlarge, 2 shard(s) x 3 nodes | 6 | 730 | node-hour | 0.617 | 2,702.46 | MemoryDB reserved node 1yr no upfront | 1,839.60 |
| MemoryDB | us-east-1 | Amazon MemoryDB | memorydb-cell-1 standby | db.r7g.xlarge, 2 shard(s) x 3 nodes | 6 | 730 | node-hour | 0.617 | 2,702.46 | MemoryDB reserved node 1yr no upfront | 1,839.60 |
| MemoryDB | us-east-1 | Amazon MemoryDB | memorydb-cell-2 standby | db.r7g.xlarge, 2 shard(s) x 3 nodes | 6 | 730 | node-hour | 0.617 | 2,702.46 | MemoryDB reserved node 1yr no upfront | 1,839.60 |
| MemoryDB | us-east-1 | Amazon MemoryDB | memorydb-cell-3 standby | db.r7g.xlarge, 2 shard(s) x 3 nodes | 6 | 730 | node-hour | 0.617 | 2,702.46 | MemoryDB reserved node 1yr no upfront | 1,839.60 |
| MemoryDB | us-east-1 | Amazon MemoryDB | memorydb-spare standby | db.r7g.xlarge, 2 shard(s) x 3 nodes | 6 | 730 | node-hour | 0.617 | 2,702.46 | MemoryDB reserved node 1yr no upfront | 1,839.60 |
| MemoryDB | eu-central-1 | Amazon MemoryDB | data written | all cells | 6,220 |  | GB | 0.2 | 1,244.00 | on-demand | 1,244.00 |
| EKS | eu-central-1 | Amazon EKS | control planes | 4 cells, spare, analytics | 6 | 730 | cluster-hour | 0.1 | 438.00 | on-demand | 438.00 |
| EKS | us-east-1 | Amazon EKS | control planes, standby | 4 cells, spare | 5 | 730 | cluster-hour | 0.1 | 365.00 | on-demand | 365.00 |
| EKS nodes | eu-central-1 | Amazon EC2 | bootstrap node groups, 3 per cluster | m7g.large, Linux, shared tenancy | 18 | 730 | instance-hour | 0.0978 | 1,285.09 | Compute SP 1yr no upfront, 80% covered | 1,040.16 |
| EKS nodes | eu-central-1 | Amazon EC2 | payments pool, 4 working cells (router min 20, drainer 3, scheduler 5) | m7g.4xlarge, Linux, shared tenancy | 12 | 730 | instance-hour | 0.7821 | 6,851.20 | Compute SP 1yr no upfront, 80% covered | 5,549.11 |
| EKS nodes | eu-central-1 | Amazon EC2 | payments pool, spare cell (same minimum replicas) | m7g.4xlarge, Linux, shared tenancy | 3 | 730 | instance-hour | 0.7821 | 1,712.80 | Compute SP 1yr no upfront, 80% covered | 1,387.28 |
| EKS nodes | eu-central-1 | Amazon EC2 | workers pool, platform add-ons of 5 cell clusters | m7g.2xlarge, Linux, shared tenancy | 5 | 730 | instance-hour | 0.391 | 1,427.15 | Compute SP 1yr no upfront, 80% covered | 1,156.17 |
| EKS nodes | eu-central-1 | Amazon EC2 | cde pool, locker (min 5 pods) | m7g.xlarge, Linux, shared tenancy | 3 | 730 | instance-hour | 0.1955 | 428.15 | Compute SP 1yr no upfront, 80% covered | 346.85 |
| EKS nodes | eu-central-1 | Amazon EC2 | analytics stateful pool, ClickHouse 4 shards x 2 replicas | r7g.2xlarge, Linux, shared tenancy | 8 | 730 | instance-hour | 0.5168 | 3,018.11 | Compute SP 1yr no upfront, 80% covered | 2,352.82 |
| EKS nodes | eu-central-1 | Amazon EC2 | analytics stateful pool, ClickHouse Keeper | m7g.large, Linux, shared tenancy | 3 | 730 | instance-hour | 0.0978 | 214.18 | Compute SP 1yr no upfront, 80% covered | 173.36 |
| EKS nodes | eu-central-1 | Amazon EC2 | analytics workers pool | m7g.2xlarge, Linux, shared tenancy | 2 | 730 | instance-hour | 0.391 | 570.86 | Compute SP 1yr no upfront, 80% covered | 462.47 |
| EKS nodes | us-east-1 | Amazon EC2 | bootstrap node groups, standby | m7g.large, Linux, shared tenancy | 15 | 730 | instance-hour | 0.0816 | 893.52 | Compute SP 1yr no upfront, 80% covered | 703.43 |
| EKS nodes | us-east-1 | Amazon EC2 | payments pool, 5 standby clusters (40 vCPU cap each) | m7g.4xlarge, Linux, shared tenancy | 10 | 730 | instance-hour | 0.6528 | 4,765.44 | Compute SP 1yr no upfront, 80% covered | 3,753.95 |
| EKS nodes | us-east-1 | Amazon EC2 | payments pool, 5 standby clusters (remainder of the cap) | m7g.2xlarge, Linux, shared tenancy | 5 | 730 | instance-hour | 0.3264 | 1,191.36 | Compute SP 1yr no upfront, 80% covered | 938.49 |
| EKS nodes | us-east-1 | Amazon EC2 | cde pool, standby locker | m7g.xlarge, Linux, shared tenancy | 3 | 730 | instance-hour | 0.1632 | 357.41 | Compute SP 1yr no upfront, 80% covered | 281.55 |
| EKS nodes | eu-central-1 | Amazon EBS | ClickHouse data volumes | gp3, 8 x 1,000 GB | 8,000 |  | GB-month | 0.0952 | 761.60 | on-demand | 761.60 |
| EKS nodes | eu-central-1 | Amazon EBS | node volumes (4 GiB OS + 80 GiB data) | gp3, 54 nodes x 84 GB | 4,536 |  | GB-month | 0.0952 | 431.83 | on-demand | 431.83 |
| EKS nodes | us-east-1 | Amazon EBS | node volumes (4 GiB OS + 80 GiB data) | gp3, 33 nodes x 84 GB | 2,772 |  | GB-month | 0.08 | 221.76 | on-demand | 221.76 |
| Analytics | eu-central-1 | Amazon MSK | brokers | kafka.m7g.xlarge, 3 AZ | 9 | 730 | broker-hour | 0.4888 | 3,211.42 | on-demand | 3,211.42 |
| Analytics | eu-central-1 | Amazon MSK | broker storage | 9 x 2,000 GB | 18,000 |  | GB-month | 0.119 | 2,142.00 | on-demand | 2,142.00 |
| Analytics | eu-central-1 | Amazon OpenSearch Service | data nodes | r7g.xlarge.search, 3 AZ | 6 | 730 | instance-hour | 0.429 | 1,879.02 | OpenSearch RI 1yr no upfront | 1,296.48 |
| Analytics | eu-central-1 | Amazon OpenSearch Service | dedicated masters | m7g.large.search | 3 | 730 | instance-hour | 0.162 | 354.78 | OpenSearch RI 1yr no upfront | 245.28 |
| Analytics | eu-central-1 | Amazon OpenSearch Service | UltraWarm nodes | ultrawarm1.medium.search | 2 | 730 | instance-hour | 0.284 | 414.64 | on-demand | 414.64 |
| Analytics | eu-central-1 | Amazon OpenSearch Service | data node storage | gp3, 6 x 1,024 GB | 6,144 |  | GB-month | 0.1452 | 892.11 | on-demand | 892.11 |
| Analytics | eu-central-1 | Amazon OpenSearch Service | UltraWarm managed storage | indices older than 30 days | 1,000 |  | GB-month | 0.026 | 26.00 | on-demand | 26.00 |
| Network | eu-central-1 | Amazon VPC | interface endpoints, workload VPC | 9 services x 3 AZ | 27 | 730 | endpoint-hour | 0.012 | 236.52 | on-demand | 236.52 |
| Network | us-east-1 | Amazon VPC | interface endpoints, workload VPC | 9 services x 3 AZ | 27 | 730 | endpoint-hour | 0.01 | 197.10 | on-demand | 197.10 |
| Network | us-east-2 | Amazon VPC | interface endpoints, workload VPC | 9 services x 3 AZ | 27 | 730 | endpoint-hour | 0.01 | 197.10 | on-demand | 197.10 |
| Network | eu-central-1 | Amazon VPC | interface endpoint data processed | AWS API traffic kept off NAT | 2,000 |  | GB | 0.01 | 20.00 | on-demand | 20.00 |
| Network | eu-central-1 | AWS Network Firewall | firewall endpoints, egress VPC | 3 AZ | 3 | 730 | endpoint-hour | 0.395 | 865.05 | on-demand | 865.05 |
| Network | eu-central-1 | Amazon VPC | NAT gateways behind the firewall | 3 AZ; hours and GB waived by the firewall endpoints | 3 | 730 | gateway-hour | 0 | 0.00 | on-demand | 0.00 |
| Network | eu-central-1 | Amazon VPC | public IPv4 of the NAT gateways | 3 addresses | 3 | 730 | address-hour | 0.005 | 10.95 | on-demand | 10.95 |
| Network | eu-central-1 | AWS Transit Gateway | VPC attachments, workload and egress | 2 attachments | 2 | 730 | attachment-hour | 0.06 | 87.60 | on-demand | 87.60 |
| Network | us-east-1 | AWS Network Firewall | firewall endpoints, egress VPC | 3 AZ | 3 | 730 | endpoint-hour | 0.395 | 865.05 | on-demand | 865.05 |
| Network | us-east-1 | Amazon VPC | NAT gateways behind the firewall | 3 AZ; hours and GB waived by the firewall endpoints | 3 | 730 | gateway-hour | 0 | 0.00 | on-demand | 0.00 |
| Network | us-east-1 | Amazon VPC | public IPv4 of the NAT gateways | 3 addresses | 3 | 730 | address-hour | 0.005 | 10.95 | on-demand | 10.95 |
| Network | us-east-1 | AWS Transit Gateway | VPC attachments, workload and egress | 2 attachments | 2 | 730 | attachment-hour | 0.05 | 73.00 | on-demand | 73.00 |
| Network | eu-central-1 | AWS Network Firewall | traffic processed | PSP calls and outgoing webhooks | 10,370 |  | GB | 0.065 | 674.05 | on-demand | 674.05 |
| Network | eu-central-1 | AWS Transit Gateway | data processed | egress traffic through two attachments | 20,740 |  | GB | 0.02 | 414.80 | on-demand | 414.80 |
| Network | global | AWS Global Accelerator | accelerator | fixed fee | 1 | 730 | accelerator-hour | 0.025 | 18.25 | on-demand | 18.25 |
| Network | global | AWS Global Accelerator | DT-Premium, Europe to Europe | API responses | 8,710 |  | GB | 0.015 | 130.65 | on-demand | 130.65 |
| Network | eu-central-1 | Elastic Load Balancing | NLB of the payments gateway | one per region with cells | 1 | 730 | LB-hour | 0.027 | 19.71 | on-demand | 19.71 |
| Network | eu-central-1 | Elastic Load Balancing | NLB capacity units | average LCU | 10 | 730 | LCU-hour | 0.006 | 43.80 | on-demand | 43.80 |
| Network | us-east-1 | Elastic Load Balancing | NLB of the payments gateway | one per region with cells | 1 | 730 | LB-hour | 0.0225 | 16.43 | on-demand | 16.43 |
| Network | us-east-1 | Elastic Load Balancing | NLB capacity units | average LCU | 1 | 730 | LCU-hour | 0.006 | 4.38 | on-demand | 4.38 |
| Data transfer | eu-central-1 | AWS Data Transfer | out to the internet | PSP requests and API responses, 19,080 GB, tiered | 1 |  | month | 1673 | 1,673.00 | on-demand | 1,673.00 |
| Data transfer | eu-central-1 | AWS Data Transfer | cross-AZ | router to MemoryDB and RDS Proxy, producers to MSK | 15,350 |  | GB | 0.02 | 307.00 | on-demand | 307.00 |
| Edge | us-east-1 | Amazon CloudFront | panel distribution, data out | PriceClass_100, Europe | 50 |  | GB | 0.085 | 4.25 | on-demand | 4.25 |
| Edge | us-east-1 | Amazon CloudFront | panel HTTPS requests | Europe | 5,000,000 |  | request | 1.2e-06 | 6.00 | on-demand | 6.00 |
| Edge | us-east-1 | AWS WAF | web ACL | panel | 1 |  | ACL-month | 5 | 5.00 | on-demand | 5.00 |
| Edge | us-east-1 | AWS WAF | rules | managed groups and rate rules | 10 |  | rule-month | 1 | 10.00 | on-demand | 10.00 |
| Edge | us-east-1 | AWS WAF | requests | panel | 5,000,000 |  | request | 6e-07 | 3.00 | on-demand | 3.00 |
| Edge | global | Amazon Route 53 | hosted zone | public zone of the environment | 1 |  | zone-month | 0.5 | 0.50 | on-demand | 0.50 |
| Data services | eu-central-1 | Amazon DynamoDB | merchant-cell map reads | on-demand | 50,000,000 |  | read request unit | 1.525e-07 | 7.62 | on-demand | 7.62 |
| Data services | eu-central-1 | Amazon DynamoDB | merchant-cell map writes and replicated writes | on-demand | 300,000 |  | write request unit | 7.625e-07 | 0.23 | on-demand | 0.23 |
| Backup and S3 | eu-central-1 | Amazon S3 | backup and event archive, Standard (days 0-7) | backups/, exports/, events/ | 1,500 |  | GB-month | 0.0245 | 36.75 | on-demand | 36.75 |
| Backup and S3 | eu-central-1 | Amazon S3 | Glacier Instant Retrieval (days 7-14) | D5 | 1,500 |  | GB-month | 0.005 | 7.50 | on-demand | 7.50 |
| Backup and S3 | eu-central-1 | Amazon S3 | Glacier Flexible Retrieval (days 14-35) | D5 | 4,500 |  | GB-month | 0.00405 | 18.22 | on-demand | 18.22 |
| Backup and S3 | eu-central-1 | Amazon S3 | monthly 7-year archive, Deep Archive | first-year average | 6,000 |  | GB-month | 0.0018 | 10.80 | on-demand | 10.80 |
| Backup and S3 | eu-central-1 | Amazon S3 | Replication Time Control to 2 regions | new objects x 2 | 13,000 |  | GB | 0.015 | 195.00 | on-demand | 195.00 |
| Data transfer | eu-central-1 | AWS Data Transfer | S3 replication to the recovery regions | inter-region | 13,000 |  | GB | 0.02 | 260.00 | on-demand | 260.00 |
| Backup and S3 | us-east-1 | Amazon S3 | locked replica bucket, Glacier IR | 35 days | 6,500 |  | GB-month | 0.004 | 26.00 | on-demand | 26.00 |
| Backup and S3 | us-east-2 | Amazon S3 | locked replica bucket, Glacier IR | 35 days | 6,500 |  | GB-month | 0.004 | 26.00 | on-demand | 26.00 |
| Backup and S3 | eu-central-1 | AWS Backup | Aurora snapshots in the vault | 35 days | 12,900 |  | GB-month | 0.023 | 296.70 | on-demand | 296.70 |
| Backup and S3 | us-east-1 | AWS Backup | Aurora snapshots in the vault | 35 days | 12,900 |  | GB-month | 0.021 | 270.90 | on-demand | 270.90 |
| Backup and S3 | us-east-2 | AWS Backup | Aurora snapshots in the vault | 35 days | 12,900 |  | GB-month | 0.021 | 270.90 | on-demand | 270.90 |
| Data transfer | eu-central-1 | AWS Data Transfer | backup copies to us-east-1 and us-east-2 | inter-region | 12,400 |  | GB | 0.02 | 248.00 | on-demand | 248.00 |
| Logs and security | eu-central-1 | Amazon CloudWatch | EKS control plane logs ingested | 5 log types, 11 clusters | 660 |  | GB | 0.63 | 415.80 | on-demand | 415.80 |
| Logs and security | eu-central-1 | Amazon CloudWatch | log storage | 365-day retention, steady state | 8,030 |  | GB-month | 0.0324 | 260.17 | on-demand | 260.17 |
| Logs and security | eu-central-1 | Amazon CloudWatch | VPC flow logs and firewall logs to S3 | vended log delivery | 800 |  | GB | 0.285 | 228.00 | on-demand | 228.00 |
| Logs and security | eu-central-1 | AWS KMS | customer managed keys | 10 per region with replicas, plus service keys | 40 |  | key-month | 1 | 40.00 | on-demand | 40.00 |
| Logs and security | eu-central-1 | AWS KMS | requests |  | 20,000,000 |  | request | 3e-06 | 60.00 | on-demand | 60.00 |
| Logs and security | eu-central-1 | AWS Secrets Manager | secrets | with replicas | 60 |  | secret-month | 0.4 | 24.00 | on-demand | 24.00 |
| Logs and security | eu-central-1 | Amazon GuardDuty | RDS protection | Aurora vCPU | 480 |  | vCPU-month | 1.23 | 590.40 | on-demand | 590.40 |
| Logs and security | eu-central-1 | Amazon GuardDuty | EKS runtime monitoring | 656 node vCPU, tiered | 1 |  | month | 1109.76 | 1,109.76 | on-demand | 1,109.76 |
| Logs and security | eu-central-1 | Amazon GuardDuty | CloudTrail, VPC flow and DNS analysis | foundational | 300 |  | GB | 1.15 | 345.00 | on-demand | 345.00 |
| Logs and security | eu-central-1 | AWS Security Hub | security checks | 3 regions | 60,000 |  | check | 0.001 | 60.00 | on-demand | 60.00 |
| Logs and security | eu-central-1 | AWS Config | configuration items | node and ENI churn | 50,000 |  | item | 0.003 | 150.00 | on-demand | 150.00 |
| Logs and security | eu-central-1 | AWS Config | conformance pack evaluations |  | 100,000 |  | evaluation | 0.001 | 100.00 | on-demand | 100.00 |
| Logs and security | eu-central-1 | Amazon Inspector | EC2 scanning | nodes | 87 | 730 | instance-hour | 0.0021 | 133.37 | on-demand | 133.37 |
| **Total** | | | | | | | | | **161,487.33** | | **129,880.98** |
