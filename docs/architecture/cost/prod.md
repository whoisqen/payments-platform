# Cost of prod

Monthly cost at the target load, from the AWS Price List (eu-central-1, us-east-1, global). Method and assumptions: [README.md](README.md).

- Sizing: `config/environments/prod.yaml`, stacks in `infra/live/prod/`, replicas from the chart defaults in `deploy/charts/*/values.yaml`.
- eu-central-1 runs 4 working cells, the spare and the locker behind RDS Proxy. Each working cell has a `db.r7g.12xlarge` writer and a `db.r7g.4xlarge` reader on I/O-Optimized storage. The spare runs 2 x `db.r7g.2xlarge`, 1 MemoryDB shard and 3 pods of each workload, and the locker 2 x `db.r7g.4xlarge`, both on Standard storage.
- us-east-1 is the hot standby at the working size ([ADR-0019](../../adr/0019-hot-standby-recovery-region.md)): the same 5 cell clusters, node pools and MemoryDB, one Aurora instance per global secondary with the writer class of its working cluster, RDS Proxy, the egress path, the NLB and the panel edge. Analytics is not mirrored: D7 rebuilds MSK from the S3 archive.
- The us-east-1 Aurora unit prices are derived from the Price List rates of the same family: `db.r7g` scales linearly with size, and Standard is the I/O-Optimized rate divided by 1.3, as the eu-central-1 rows show.
- Logs and security lines in eu-central-1 count the clusters, nodes and Aurora vCPU of both regions.
- Compute is the target capacity: router at 60 RPS per pod, so the HPA floor of 20 pods per cell holds the daily peak of 480 TPS.
- Analytics: MSK 3 x `kafka.m7g.large`, OpenSearch 3 data nodes, ClickHouse 2 shards x 2 replicas.
- EKS control-plane logs stay 365 days in CloudWatch and stream through Firehose into the log archive.
- Committed column: Database Savings Plan 1 year no upfront for Aurora, OpenSearch and DynamoDB; MemoryDB reserved 1 year no upfront; Compute Savings Plan 1 year no upfront on 80% of EC2.

Total: **149,044 USD/month on demand**, **121,242 USD/month committed**.

## By group

| Group | On-demand (USD/month) | Committed (USD/month) |
|---|---:|---:|
| Aurora | 84,819.30 | 70,050.20 |
| MemoryDB | 28,010.18 | 19,456.04 |
| EKS nodes | 21,976.78 | 17,758.19 |
| Network | 3,688.29 | 3,688.29 |
| Logs and security | 3,514.26 | 3,514.26 |
| Analytics | 3,073.44 | 2,814.58 |
| Data transfer | 2,358.00 | 2,358.00 |
| EKS | 803.00 | 803.00 |
| Backup and S3 | 764.37 | 764.37 |
| Edge | 28.75 | 28.75 |
| Data services | 7.77 | 6.37 |
| **Total** | **149,044.14** | **121,242.05** |

## Line items

Hours are per month (730 for 24/7). Usage lines have no hours: quantity times unit price.

| Group | Region | Service | Resource | Configuration | Quantity | Hours | Unit | Unit price (USD) | Monthly on-demand (USD) | Pricing model | Monthly committed (USD) |
|---|---|---|---|---|---:|---:|---|---:|---:|---|---:|
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-cell-0 writer | db.r7g.12xlarge, I/O-Optimized | 1 | 730 | instance-hour | 10.381 | 7,578.13 | Database SP 1yr no upfront | 6,062.50 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-cell-0 reader | db.r7g.4xlarge, I/O-Optimized | 1 | 730 | instance-hour | 3.461 | 2,526.53 | Database SP 1yr no upfront | 2,021.22 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-cell-0 storage | I/O-Optimized storage | 2,000 |  | GB-month | 0.268 | 536.00 | on-demand | 536.00 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-cell-1 writer | db.r7g.12xlarge, I/O-Optimized | 1 | 730 | instance-hour | 10.381 | 7,578.13 | Database SP 1yr no upfront | 6,062.50 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-cell-1 reader | db.r7g.4xlarge, I/O-Optimized | 1 | 730 | instance-hour | 3.461 | 2,526.53 | Database SP 1yr no upfront | 2,021.22 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-cell-1 storage | I/O-Optimized storage | 2,000 |  | GB-month | 0.268 | 536.00 | on-demand | 536.00 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-cell-2 writer | db.r7g.12xlarge, I/O-Optimized | 1 | 730 | instance-hour | 10.381 | 7,578.13 | Database SP 1yr no upfront | 6,062.50 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-cell-2 reader | db.r7g.4xlarge, I/O-Optimized | 1 | 730 | instance-hour | 3.461 | 2,526.53 | Database SP 1yr no upfront | 2,021.22 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-cell-2 storage | I/O-Optimized storage | 2,000 |  | GB-month | 0.268 | 536.00 | on-demand | 536.00 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-cell-3 writer | db.r7g.12xlarge, I/O-Optimized | 1 | 730 | instance-hour | 10.381 | 7,578.13 | Database SP 1yr no upfront | 6,062.50 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-cell-3 reader | db.r7g.4xlarge, I/O-Optimized | 1 | 730 | instance-hour | 3.461 | 2,526.53 | Database SP 1yr no upfront | 2,021.22 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-cell-3 storage | I/O-Optimized storage | 2,000 |  | GB-month | 0.268 | 536.00 | on-demand | 536.00 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-spare writer | db.r7g.2xlarge, Standard | 1 | 730 | instance-hour | 1.331 | 971.63 | Database SP 1yr no upfront | 777.30 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-spare reader | db.r7g.2xlarge, Standard | 1 | 730 | instance-hour | 1.331 | 971.63 | Database SP 1yr no upfront | 777.30 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-spare storage | Standard storage | 100 |  | GB-month | 0.119 | 11.90 | on-demand | 11.90 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-locker writer | db.r7g.4xlarge, Standard | 1 | 730 | instance-hour | 2.662 | 1,943.26 | Database SP 1yr no upfront | 1,554.61 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-locker reader | db.r7g.4xlarge, Standard | 1 | 730 | instance-hour | 2.662 | 1,943.26 | Database SP 1yr no upfront | 1,554.61 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-locker storage | Standard storage | 500 |  | GB-month | 0.119 | 59.50 | on-demand | 59.50 |
| Aurora | eu-central-1 | Amazon RDS Proxy | proxies of 6 clusters | billed per vCPU of the cluster instances | 304 | 730 | vCPU-hour | 0.018 | 3,994.56 | on-demand | 3,994.56 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | backup storage above the free allowance | 35-day PITR | 8,600 |  | GB-month | 0.023 | 197.80 | on-demand | 197.80 |
| Aurora | us-east-1 | Amazon Aurora PostgreSQL | global secondaries storage, 4 cells | I/O-Optimized storage | 8,000 |  | GB-month | 0.225 | 1,800.00 | on-demand | 1,800.00 |
| Aurora | us-east-1 | Amazon Aurora PostgreSQL | global secondaries storage, spare and locker | Standard storage | 600 |  | GB-month | 0.1 | 60.00 | on-demand | 60.00 |
| Aurora | us-east-1 | Amazon Aurora PostgreSQL | replicated write I/O into this region | Aurora Global Database | 1,550,000,000 |  | I/O | 2.2e-07 | 341.00 | on-demand | 341.00 |
| Aurora | us-east-1 | Amazon Aurora PostgreSQL | aurora-cell-0 standby instance | db.r7g.12xlarge, I/O-Optimized | 1 | 730 | instance-hour | 8.622 | 6,294.06 | Database SP 1yr no upfront | 5,035.25 |
| Aurora | us-east-1 | Amazon Aurora PostgreSQL | aurora-cell-1 standby instance | db.r7g.12xlarge, I/O-Optimized | 1 | 730 | instance-hour | 8.622 | 6,294.06 | Database SP 1yr no upfront | 5,035.25 |
| Aurora | us-east-1 | Amazon Aurora PostgreSQL | aurora-cell-2 standby instance | db.r7g.12xlarge, I/O-Optimized | 1 | 730 | instance-hour | 8.622 | 6,294.06 | Database SP 1yr no upfront | 5,035.25 |
| Aurora | us-east-1 | Amazon Aurora PostgreSQL | aurora-cell-3 standby instance | db.r7g.12xlarge, I/O-Optimized | 1 | 730 | instance-hour | 8.622 | 6,294.06 | Database SP 1yr no upfront | 5,035.25 |
| Aurora | us-east-1 | Amazon Aurora PostgreSQL | aurora-spare standby instance | db.r7g.2xlarge, Standard | 1 | 730 | instance-hour | 1.105 | 806.65 | Database SP 1yr no upfront | 645.32 |
| Aurora | us-east-1 | Amazon Aurora PostgreSQL | aurora-locker standby instance | db.r7g.4xlarge, Standard | 1 | 730 | instance-hour | 2.211 | 1,614.03 | Database SP 1yr no upfront | 1,291.22 |
| Aurora | us-east-1 | Amazon RDS Proxy | proxies of 6 clusters, standby | billed per vCPU of the cluster instances | 216 | 730 | vCPU-hour | 0.015 | 2,365.20 | on-demand | 2,365.20 |
| Data transfer | eu-central-1 | AWS Data Transfer | Aurora global replication to us-east-1 | inter-region | 6,200 |  | GB | 0.02 | 124.00 | on-demand | 124.00 |
| MemoryDB | eu-central-1 | Amazon MemoryDB | memorydb-cell-0 | db.r7g.xlarge, 2 shard(s) x 3 nodes | 6 | 730 | node-hour | 0.741 | 3,245.58 | MemoryDB reserved node 1yr no upfront | 2,207.52 |
| MemoryDB | eu-central-1 | Amazon MemoryDB | memorydb-cell-1 | db.r7g.xlarge, 2 shard(s) x 3 nodes | 6 | 730 | node-hour | 0.741 | 3,245.58 | MemoryDB reserved node 1yr no upfront | 2,207.52 |
| MemoryDB | eu-central-1 | Amazon MemoryDB | memorydb-cell-2 | db.r7g.xlarge, 2 shard(s) x 3 nodes | 6 | 730 | node-hour | 0.741 | 3,245.58 | MemoryDB reserved node 1yr no upfront | 2,207.52 |
| MemoryDB | eu-central-1 | Amazon MemoryDB | memorydb-cell-3 | db.r7g.xlarge, 2 shard(s) x 3 nodes | 6 | 730 | node-hour | 0.741 | 3,245.58 | MemoryDB reserved node 1yr no upfront | 2,207.52 |
| MemoryDB | eu-central-1 | Amazon MemoryDB | memorydb-spare | db.r7g.xlarge, 1 shard(s) x 3 nodes | 3 | 730 | node-hour | 0.741 | 1,622.79 | MemoryDB reserved node 1yr no upfront | 1,103.76 |
| MemoryDB | us-east-1 | Amazon MemoryDB | memorydb-cell-0 standby | db.r7g.xlarge, 2 shard(s) x 3 nodes | 6 | 730 | node-hour | 0.617 | 2,702.46 | MemoryDB reserved node 1yr no upfront | 1,839.60 |
| MemoryDB | us-east-1 | Amazon MemoryDB | memorydb-cell-1 standby | db.r7g.xlarge, 2 shard(s) x 3 nodes | 6 | 730 | node-hour | 0.617 | 2,702.46 | MemoryDB reserved node 1yr no upfront | 1,839.60 |
| MemoryDB | us-east-1 | Amazon MemoryDB | memorydb-cell-2 standby | db.r7g.xlarge, 2 shard(s) x 3 nodes | 6 | 730 | node-hour | 0.617 | 2,702.46 | MemoryDB reserved node 1yr no upfront | 1,839.60 |
| MemoryDB | us-east-1 | Amazon MemoryDB | memorydb-cell-3 standby | db.r7g.xlarge, 2 shard(s) x 3 nodes | 6 | 730 | node-hour | 0.617 | 2,702.46 | MemoryDB reserved node 1yr no upfront | 1,839.60 |
| MemoryDB | us-east-1 | Amazon MemoryDB | memorydb-spare standby | db.r7g.xlarge, 1 shard(s) x 3 nodes | 3 | 730 | node-hour | 0.617 | 1,351.23 | MemoryDB reserved node 1yr no upfront | 919.80 |
| MemoryDB | eu-central-1 | Amazon MemoryDB | data written | all cells | 6,220 |  | GB | 0.2 | 1,244.00 | on-demand | 1,244.00 |
| EKS | eu-central-1 | Amazon EKS | control planes | 4 cells, spare, analytics | 6 | 730 | cluster-hour | 0.1 | 438.00 | on-demand | 438.00 |
| EKS | us-east-1 | Amazon EKS | control planes, standby | 4 cells, spare | 5 | 730 | cluster-hour | 0.1 | 365.00 | on-demand | 365.00 |
| EKS nodes | eu-central-1 | Amazon EC2 | bootstrap node groups, 3 per cluster | m7g.large, Linux, shared tenancy | 18 | 730 | instance-hour | 0.0978 | 1,285.09 | Compute SP 1yr no upfront, 80% covered | 1,040.16 |
| EKS nodes | eu-central-1 | Amazon EC2 | payments pool, 4 working cells (router min 20, drainer 3, scheduler 5) | m7g.4xlarge, Linux, shared tenancy | 12 | 730 | instance-hour | 0.7821 | 6,851.20 | Compute SP 1yr no upfront, 80% covered | 5,549.11 |
| EKS nodes | eu-central-1 | Amazon EC2 | payments pool, spare cell (3 pods of each workload) | m7g.2xlarge, Linux, shared tenancy | 1 | 730 | instance-hour | 0.391 | 285.43 | Compute SP 1yr no upfront, 80% covered | 231.18 |
| EKS nodes | eu-central-1 | Amazon EC2 | workers pool, platform add-ons of 5 cell clusters | m7g.2xlarge, Linux, shared tenancy | 5 | 730 | instance-hour | 0.391 | 1,427.15 | Compute SP 1yr no upfront, 80% covered | 1,156.17 |
| EKS nodes | eu-central-1 | Amazon EC2 | cde pool, locker (min 5 pods) | m7g.xlarge, Linux, shared tenancy | 3 | 730 | instance-hour | 0.1955 | 428.15 | Compute SP 1yr no upfront, 80% covered | 346.85 |
| EKS nodes | eu-central-1 | Amazon EC2 | analytics stateful pool, ClickHouse 2 shards x 2 replicas | r7g.2xlarge, Linux, shared tenancy | 4 | 730 | instance-hour | 0.5168 | 1,509.06 | Compute SP 1yr no upfront, 80% covered | 1,176.41 |
| EKS nodes | eu-central-1 | Amazon EC2 | analytics stateful pool, ClickHouse Keeper | m7g.large, Linux, shared tenancy | 3 | 730 | instance-hour | 0.0978 | 214.18 | Compute SP 1yr no upfront, 80% covered | 173.36 |
| EKS nodes | eu-central-1 | Amazon EC2 | analytics workers pool | m7g.2xlarge, Linux, shared tenancy | 2 | 730 | instance-hour | 0.391 | 570.86 | Compute SP 1yr no upfront, 80% covered | 462.47 |
| EKS nodes | eu-central-1 | Amazon EBS | ClickHouse data volumes | gp3, 4 x 1,000 GB | 4,000 |  | GB-month | 0.0952 | 380.80 | on-demand | 380.80 |
| EKS nodes | eu-central-1 | Amazon EBS | node volumes (4 GiB OS + 80 GiB data) | gp3, 48 nodes x 84 GB | 4,032 |  | GB-month | 0.0952 | 383.85 | on-demand | 383.85 |
| EKS nodes | us-east-1 | Amazon EC2 | bootstrap node groups, 3 per standby cluster | m7g.large, Linux, shared tenancy | 15 | 730 | instance-hour | 0.0816 | 893.52 | Compute SP 1yr no upfront, 80% covered | 703.43 |
| EKS nodes | us-east-1 | Amazon EC2 | payments pool, 4 standby cells (working-cell floors) | m7g.4xlarge, Linux, shared tenancy | 12 | 730 | instance-hour | 0.6528 | 5,718.53 | Compute SP 1yr no upfront, 80% covered | 4,504.74 |
| EKS nodes | us-east-1 | Amazon EC2 | payments pool, standby spare cell | m7g.2xlarge, Linux, shared tenancy | 1 | 730 | instance-hour | 0.3264 | 238.27 | Compute SP 1yr no upfront, 80% covered | 187.70 |
| EKS nodes | us-east-1 | Amazon EC2 | workers pool, platform add-ons of 5 standby clusters | m7g.2xlarge, Linux, shared tenancy | 5 | 730 | instance-hour | 0.3264 | 1,191.36 | Compute SP 1yr no upfront, 80% covered | 938.49 |
| EKS nodes | us-east-1 | Amazon EC2 | cde pool, standby locker | m7g.xlarge, Linux, shared tenancy | 3 | 730 | instance-hour | 0.1632 | 357.41 | Compute SP 1yr no upfront, 80% covered | 281.55 |
| EKS nodes | us-east-1 | Amazon EBS | node volumes (4 GiB OS + 80 GiB data) | gp3, 36 nodes x 84 GB | 3,024 |  | GB-month | 0.08 | 241.92 | on-demand | 241.92 |
| Analytics | eu-central-1 | Amazon MSK | brokers | kafka.m7g.large, 3 AZ | 3 | 730 | broker-hour | 0.2445 | 535.46 | on-demand | 535.46 |
| Analytics | eu-central-1 | Amazon MSK | broker storage | 3 x 1,000 GB | 3,000 |  | GB-month | 0.119 | 357.00 | on-demand | 357.00 |
| Analytics | eu-central-1 | Amazon OpenSearch Service | data nodes | r7g.xlarge.search, 3 AZ | 3 | 730 | instance-hour | 0.429 | 939.51 | Database SP 1yr no upfront | 751.61 |
| Analytics | eu-central-1 | Amazon OpenSearch Service | dedicated masters | m7g.large.search | 3 | 730 | instance-hour | 0.162 | 354.78 | Database SP 1yr no upfront | 283.82 |
| Analytics | eu-central-1 | Amazon OpenSearch Service | UltraWarm nodes | ultrawarm1.medium.search | 2 | 730 | instance-hour | 0.284 | 414.64 | on-demand | 414.64 |
| Analytics | eu-central-1 | Amazon OpenSearch Service | data node storage | gp3, 3 x 1,024 GB | 3,072 |  | GB-month | 0.1452 | 446.05 | on-demand | 446.05 |
| Analytics | eu-central-1 | Amazon OpenSearch Service | UltraWarm managed storage | indices older than 30 days | 1,000 |  | GB-month | 0.026 | 26.00 | on-demand | 26.00 |
| Network | eu-central-1 | Amazon VPC | interface endpoints, workload VPC | 9 services x 3 AZ | 27 | 730 | endpoint-hour | 0.012 | 236.52 | on-demand | 236.52 |
| Network | us-east-1 | Amazon VPC | interface endpoints, workload VPC | 9 services x 3 AZ | 27 | 730 | endpoint-hour | 0.01 | 197.10 | on-demand | 197.10 |
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
| Data services | eu-central-1 | Amazon DynamoDB | merchant-cell map reads | on-demand | 50,000,000 |  | read request unit | 1.525e-07 | 7.62 | Database SP 1yr no upfront | 6.25 |
| Data services | eu-central-1 | Amazon DynamoDB | merchant-cell map writes and replicated writes | on-demand | 200,000 |  | write request unit | 7.625e-07 | 0.15 | Database SP 1yr no upfront | 0.12 |
| Backup and S3 | eu-central-1 | Amazon S3 | backup and event archive, Standard (days 0-7) | backups/, exports/, events/ | 1,500 |  | GB-month | 0.0245 | 36.75 | on-demand | 36.75 |
| Backup and S3 | eu-central-1 | Amazon S3 | Glacier Instant Retrieval (days 7-14) | D5 | 1,500 |  | GB-month | 0.005 | 7.50 | on-demand | 7.50 |
| Backup and S3 | eu-central-1 | Amazon S3 | Glacier Flexible Retrieval (days 14-35) | D5 | 4,500 |  | GB-month | 0.00405 | 18.22 | on-demand | 18.22 |
| Backup and S3 | eu-central-1 | Amazon S3 | monthly 7-year archive, Deep Archive | first-year average | 6,000 |  | GB-month | 0.0018 | 10.80 | on-demand | 10.80 |
| Backup and S3 | eu-central-1 | Amazon S3 | Replication Time Control to us-east-1 | new objects | 6,500 |  | GB | 0.015 | 97.50 | on-demand | 97.50 |
| Data transfer | eu-central-1 | AWS Data Transfer | S3 replication to us-east-1 | inter-region | 6,500 |  | GB | 0.02 | 130.00 | on-demand | 130.00 |
| Backup and S3 | us-east-1 | Amazon S3 | locked replica bucket, Glacier IR | 35 days | 6,500 |  | GB-month | 0.004 | 26.00 | on-demand | 26.00 |
| Backup and S3 | eu-central-1 | AWS Backup | Aurora snapshots in the vault | 35 days | 12,900 |  | GB-month | 0.023 | 296.70 | on-demand | 296.70 |
| Backup and S3 | us-east-1 | AWS Backup | Aurora snapshots in the vault | 35 days | 12,900 |  | GB-month | 0.021 | 270.90 | on-demand | 270.90 |
| Data transfer | eu-central-1 | AWS Data Transfer | backup copies to us-east-1 | inter-region | 6,200 |  | GB | 0.02 | 124.00 | on-demand | 124.00 |
| Logs and security | eu-central-1 | Amazon CloudWatch | EKS control plane logs ingested | 5 log types, 11 clusters | 660 |  | GB | 0.63 | 415.80 | on-demand | 415.80 |
| Logs and security | eu-central-1 | Amazon CloudWatch | log storage | 365-day retention, steady state | 8,030 |  | GB-month | 0.0324 | 260.17 | on-demand | 260.17 |
| Logs and security | eu-central-1 | Amazon Data Firehose | EKS control plane logs to the log archive | subscription filter, Direct PUT ingestion | 360 |  | GB | 0.033 | 11.88 | on-demand | 11.88 |
| Logs and security | eu-central-1 | Amazon CloudWatch | VPC flow logs and firewall logs to S3 | vended log delivery | 800 |  | GB | 0.285 | 228.00 | on-demand | 228.00 |
| Logs and security | eu-central-1 | AWS KMS | customer managed keys | 10 per region with replicas, plus service keys | 40 |  | key-month | 1 | 40.00 | on-demand | 40.00 |
| Logs and security | eu-central-1 | AWS KMS | requests |  | 20,000,000 |  | request | 3e-06 | 60.00 | on-demand | 60.00 |
| Logs and security | eu-central-1 | AWS Secrets Manager | secrets | with replicas | 40 |  | secret-month | 0.4 | 16.00 | on-demand | 16.00 |
| Logs and security | eu-central-1 | Amazon GuardDuty | RDS protection | Aurora vCPU | 520 |  | vCPU-month | 1.23 | 639.60 | on-demand | 639.60 |
| Logs and security | eu-central-1 | Amazon GuardDuty | EKS runtime monitoring | 624 node vCPU, tiered | 1 |  | month | 1079.04 | 1,079.04 | on-demand | 1,079.04 |
| Logs and security | eu-central-1 | Amazon GuardDuty | CloudTrail, VPC flow and DNS analysis | foundational | 300 |  | GB | 1.15 | 345.00 | on-demand | 345.00 |
| Logs and security | eu-central-1 | AWS Security Hub | security checks | 2 regions | 40,000 |  | check | 0.001 | 40.00 | on-demand | 40.00 |
| Logs and security | eu-central-1 | AWS Config | configuration items | node and ENI churn | 50,000 |  | item | 0.003 | 150.00 | on-demand | 150.00 |
| Logs and security | eu-central-1 | AWS Config | conformance pack evaluations |  | 100,000 |  | evaluation | 0.001 | 100.00 | on-demand | 100.00 |
| Logs and security | eu-central-1 | Amazon Inspector | EC2 scanning | nodes | 84 | 730 | instance-hour | 0.0021 | 128.77 | on-demand | 128.77 |
| **Total** | | | | | | | | | **149,044.14** | | **121,242.05** |
