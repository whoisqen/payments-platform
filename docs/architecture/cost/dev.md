# Cost of dev

Monthly cost at the target load, from the AWS Price List (eu-central-1, us-east-1, global). Method and assumptions: [README.md](README.md).

- Sizing: `config/environments/dev.yaml` over `config/environments/prod.yaml`, stacks in `infra/live/dev/`.
- The stacks create cell-0 and the spare (`infra/live/dev/eu-central-1/cell-0`, `spare`), each with Aurora `db.r7g.large` (no readers), MemoryDB `db.t4g.small` (1 shard x 3 nodes) and its own EKS cluster. The spare and the locker use Standard storage.
- Logs go to the central log domain in shared-services; dev pays only its VPC endpoint to it.
- dev runs in eu-central-1 alone. Its us-east-1 holds only `panel-edge`, `waf-edge` and `kms`. The egress firewall uses one endpoint.
- Payments and stateful node pools run on Spot; the cde and workers pools run on demand.
- `aurora-schedule` stops the Aurora clusters outside the working window (60 of 168 hours: 08:00-20:00 Europe/Berlin on weekdays), so their instance lines run 260.71 hours. KEDA scales the workloads to zero on the same window (`global.workingHours`), so the payments and cde nodes run 260.71 hours too. `env-up` keeps dev up outside the window. Every other line runs 730 hours.
- Commitments: none; the committed column applies the Spot planning rate only.

Total: **4,203 USD/month on demand**, **3,967 USD/month committed**.

## By group

| Group | On-demand (USD/month) | Committed (USD/month) |
|---|---:|---:|
| EKS nodes | 1,651.65 | 1,416.14 |
| Network | 700.04 | 700.04 |
| Analytics | 571.16 | 571.16 |
| Logs and security | 410.53 | 410.53 |
| Aurora | 375.49 | 375.49 |
| MemoryDB | 240.52 | 240.52 |
| EKS | 219.00 | 219.00 |
| Edge | 16.83 | 16.83 |
| Data transfer | 13.00 | 13.00 |
| Backup and S3 | 4.37 | 4.37 |
| Data services | 0.16 | 0.16 |
| **Total** | **4,202.75** | **3,967.24** |

## Line items

Hours are per month (730 for 24/7). Usage lines have no hours: quantity times unit price.

| Group | Region | Service | Resource | Configuration | Quantity | Hours | Unit | Unit price (USD) | Monthly on-demand (USD) | Pricing model | Monthly committed (USD) |
|---|---|---|---|---|---:|---:|---|---:|---:|---|---:|
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-cell-0 writer | db.r7g.large, I/O-Optimized | 1 | 260.71 | instance-hour | 0.433 | 112.89 | on-demand | 112.89 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-cell-0 storage | I/O-Optimized storage | 20 |  | GB-month | 0.268 | 5.36 | on-demand | 5.36 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-spare writer | db.r7g.large, Standard | 1 | 260.71 | instance-hour | 0.333 | 86.82 | on-demand | 86.82 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-spare storage | Standard storage | 20 |  | GB-month | 0.119 | 2.38 | on-demand | 2.38 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-locker writer | db.r7g.large, Standard | 1 | 260.71 | instance-hour | 0.333 | 86.82 | on-demand | 86.82 |
| Aurora | eu-central-1 | Amazon Aurora PostgreSQL | aurora-locker storage | Standard storage | 20 |  | GB-month | 0.119 | 2.38 | on-demand | 2.38 |
| Aurora | eu-central-1 | Amazon RDS Proxy | proxies of 3 clusters | billed per vCPU of the cluster instances | 6 | 730 | vCPU-hour | 0.018 | 78.84 | on-demand | 78.84 |
| MemoryDB | eu-central-1 | Amazon MemoryDB | memorydb-cell-0 | db.t4g.small, 1 shard(s) x 3 nodes | 3 | 730 | node-hour | 0.054 | 118.26 | on-demand | 118.26 |
| MemoryDB | eu-central-1 | Amazon MemoryDB | memorydb-spare | db.t4g.small, 1 shard(s) x 3 nodes | 3 | 730 | node-hour | 0.054 | 118.26 | on-demand | 118.26 |
| MemoryDB | eu-central-1 | Amazon MemoryDB | data written | all cells | 20 |  | GB | 0.2 | 4.00 | on-demand | 4.00 |
| EKS | eu-central-1 | Amazon EKS | control planes | cell-0, spare, analytics | 3 | 730 | cluster-hour | 0.1 | 219.00 | on-demand | 219.00 |
| EKS nodes | eu-central-1 | Amazon EC2 | bootstrap node groups, 3 per cluster | m7g.large, Linux, shared tenancy | 9 | 730 | instance-hour | 0.0978 | 642.55 | on-demand | 642.55 |
| EKS nodes | eu-central-1 | Amazon EC2 | payments pool, cell-0 and spare (working hours) | m7g.2xlarge, Linux, Spot | 2 | 260.71 | instance-hour | 0.391 | 203.88 | Spot at 40% of on-demand | 81.55 |
| EKS nodes | eu-central-1 | Amazon EC2 | workers pool, platform add-ons | m7g.xlarge, Linux, shared tenancy | 3 | 730 | instance-hour | 0.1955 | 428.15 | on-demand | 428.15 |
| EKS nodes | eu-central-1 | Amazon EC2 | cde pool, locker (working hours) | m7g.xlarge, Linux, shared tenancy | 1 | 260.71 | instance-hour | 0.1955 | 50.97 | on-demand | 50.97 |
| EKS nodes | eu-central-1 | Amazon EC2 | analytics stateful pool, ClickHouse 1 replica | r7g.xlarge, Linux, Spot | 1 | 730 | instance-hour | 0.2584 | 188.63 | Spot at 40% of on-demand | 75.45 |
| EKS nodes | eu-central-1 | Amazon EBS | ClickHouse data volume | gp3, 1 x 100 GB | 100 |  | GB-month | 0.0952 | 9.52 | on-demand | 9.52 |
| EKS nodes | eu-central-1 | Amazon EBS | node volumes (4 GiB OS + 80 GiB data) | gp3, 16 nodes x 84 GB | 1,344 |  | GB-month | 0.0952 | 127.95 | on-demand | 127.95 |
| Analytics | eu-central-1 | Amazon MSK | brokers | kafka.m7g.large, 3 AZ | 3 | 730 | broker-hour | 0.2445 | 535.46 | on-demand | 535.46 |
| Analytics | eu-central-1 | Amazon MSK | broker storage | 3 x 100 GB | 300 |  | GB-month | 0.119 | 35.70 | on-demand | 35.70 |
| Network | eu-central-1 | Amazon VPC | interface endpoints, workload VPC | 9 services x 3 AZ | 27 | 730 | endpoint-hour | 0.012 | 236.52 | on-demand | 236.52 |
| Network | eu-central-1 | Amazon VPC | interface endpoint data processed | AWS API traffic kept off NAT | 200 |  | GB | 0.01 | 2.00 | on-demand | 2.00 |
| Network | eu-central-1 | Amazon VPC | VPC endpoint of the central log domain | OpenSearch-managed endpoint, 3 AZ | 3 | 730 | endpoint-hour | 0.012 | 26.28 | on-demand | 26.28 |
| Network | eu-central-1 | AWS Network Firewall | firewall endpoints, egress VPC | 1 AZ | 1 | 730 | endpoint-hour | 0.395 | 288.35 | on-demand | 288.35 |
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
| Logs and security | eu-central-1 | Amazon CloudWatch | EKS control plane logs ingested | 5 log types, 3 clusters | 30 |  | GB | 0.63 | 18.90 | on-demand | 18.90 |
| Logs and security | eu-central-1 | Amazon CloudWatch | log storage | 30-day retention, steady state | 30 |  | GB-month | 0.0324 | 0.97 | on-demand | 0.97 |
| Logs and security | eu-central-1 | Amazon Data Firehose | EKS control plane logs to the log archive | subscription filter, Direct PUT ingestion | 30 |  | GB | 0.033 | 0.99 | on-demand | 0.99 |
| Logs and security | eu-central-1 | Amazon CloudWatch | VPC flow logs and firewall logs to S3 | vended log delivery | 50 |  | GB | 0.285 | 14.25 | on-demand | 14.25 |
| Logs and security | eu-central-1 | AWS KMS | customer managed keys | 10 per region with replicas, plus service keys | 40 |  | key-month | 1 | 40.00 | on-demand | 40.00 |
| Logs and security | eu-central-1 | AWS KMS | requests |  | 2,000,000 |  | request | 3e-06 | 6.00 | on-demand | 6.00 |
| Logs and security | eu-central-1 | AWS Secrets Manager | secrets | with replicas | 40 |  | secret-month | 0.4 | 16.00 | on-demand | 16.00 |
| Logs and security | eu-central-1 | Amazon GuardDuty | RDS protection | Aurora vCPU | 6 |  | vCPU-month | 1.23 | 7.38 | on-demand | 7.38 |
| Logs and security | eu-central-1 | Amazon GuardDuty | EKS runtime monitoring | 54 node vCPU, tiered | 1 |  | month | 103.68 | 103.68 | on-demand | 103.68 |
| Logs and security | eu-central-1 | Amazon GuardDuty | CloudTrail, VPC flow and DNS analysis | foundational | 30 |  | GB | 1.15 | 34.50 | on-demand | 34.50 |
| Logs and security | eu-central-1 | AWS Security Hub | security checks | 2 regions | 33,333 |  | check | 0.001 | 33.33 | on-demand | 33.33 |
| Logs and security | eu-central-1 | AWS Config | configuration items | node and ENI churn | 20,000 |  | item | 0.003 | 60.00 | on-demand | 60.00 |
| Logs and security | eu-central-1 | AWS Config | conformance pack evaluations |  | 50,000 |  | evaluation | 0.001 | 50.00 | on-demand | 50.00 |
| Logs and security | eu-central-1 | Amazon Inspector | EC2 scanning | nodes | 16 | 730 | instance-hour | 0.0021 | 24.53 | on-demand | 24.53 |
| **Total** | | | | | | | | | **4,202.75** | | **3,967.24** |
