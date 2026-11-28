# AWS Pricing Calculator entry

How to rebuild every line of [calculator-items.csv](calculator-items.csv) in the AWS Pricing Calculator (https://calculator.aws/) and share the result.
Quantities come from the environment files; this page names the calculator service, region, fields and values.

## Setup

1. Create one estimate per environment: `pay-prod`, `pay-stage`, `pay-dev`, `pay-shared-services`, `pay-central-observability`, `pay-organization`.
2. In each estimate create the groups of the `group` column (Aurora, MemoryDB, EKS, EKS nodes, Analytics, Network, Data transfer, Edge, Data services, Backup and S3, Logs and security).
3. Add each service to its group with the region of the `region` column. `global` lines (Global Accelerator, Route 53, Shield) take any region.
4. Use 730 hours a month and "Constant usage" for 24/7 lines. CI runners use 260 hours a month.
5. Enter the on-demand price model first and save. Then switch the prod lines to the committed model of [README.md](README.md) and save a second estimate (`pay-prod-committed`).
6. Select "Save and share" and paste the link below.

| Estimate | Expected monthly total (USD) | Shareable link |
|---|---:|---|
| pay-prod (on demand) | 146,889 | paste after saving |
| pay-prod-committed | 119,346 | paste after saving |
| pay-stage | 11,218 with Spot pools (12,711 all on demand) | paste after saving |
| pay-dev | 3,967 with Spot pools (4,203 all on demand) | paste after saving |
| pay-shared-services | 808 with Spot runners (1,325 all on demand) | paste after saving |
| pay-central-observability | 6,858 with the Spot workers pool and the Database Savings Plan (8,021 all on demand) | paste after saving |
| pay-organization | 421 | paste after saving |

The calculator applies its own historical Spot discount instead of the 40% planning rate, so Spot lines differ a little. It also does not apply the NAT waiver behind Network Firewall, so NAT gateways are left out of the entry.

## Prod, eu-central-1

| Group | Calculator service | Fields and values |
|---|---|---|
| Aurora | Amazon Aurora PostgreSQL-Compatible DB | Entry 1, Aurora I/O-Optimized: `db.r7g.12xlarge` x 4 (cell writers), `db.r7g.4xlarge` x 4 (cell readers), storage 8,000 GB. Entry 2, Aurora Standard: `db.r7g.2xlarge` x 2 (spare), `db.r7g.4xlarge` x 2 (locker), storage 600 GB. Utilization 100%. Pricing model: OnDemand (committed estimate: Database Savings Plans, 1 year, No Upfront). Backup storage: 8,600 GB above the free allowance. |
| Aurora | Amazon RDS Proxy | Database engine: Aurora PostgreSQL. vCPU of the target instances: 304 (4 cells x 64, spare 16, locker 32). |
| MemoryDB | Amazon MemoryDB | Node type `db.r7g.xlarge`. Shards 9 (2 per working cell x 4, 1 for the spare), replicas per shard 2, giving 27 nodes. Pricing: OnDemand (committed: Reserved, 1 year, No Upfront). Data written: 6,220 GB per month. |
| EKS | Amazon EKS | Number of clusters 6, standard support. |
| EKS nodes | Amazon EC2 | One row per line of [prod.md](prod.md) "EKS nodes": OS Linux, tenancy Shared, workload Constant usage. Instances: m7g.large x 21, m7g.4xlarge x 12, m7g.2xlarge x 8, m7g.xlarge x 3, r7g.2xlarge x 4. Pricing strategy: On-Demand (committed: Compute Savings Plans, 1 year, No upfront, then reduce coverage to 80%). EBS: General Purpose SSD (gp3), 48 nodes x 84 GB plus 4,000 GB for ClickHouse, default IOPS and throughput. |
| Analytics | Amazon MSK | Provisioned. Broker `kafka.m7g.large`, 3 brokers, storage 1,000 GB per broker. |
| Network | Amazon VPC | Interface endpoints: 9 endpoints x 3 AZ (27 ENIs) plus the log domain endpoint x 3 AZ (3 ENIs), 2,000 GB processed. Public IPv4: 3 in-use addresses. Transit Gateway: 2 VPC attachments, 20,740 GB processed. |
| Network | AWS Network Firewall | Firewall endpoints 3, data processed 10,370 GB. |
| Network | Elastic Load Balancing | Network Load Balancer x 1, 10 LCU on average (enter as processed bytes of 10 GB per hour, or new connections that produce 10 LCU). |
| Data transfer | AWS Data Transfer | Outbound to the internet: 19,080 GB. Inter-region outbound to us-east-1: 6,200 (Aurora) + 6,500 (S3) + 6,200 (Backup) GB. Intra-region (cross-AZ): 15,350 GB. |
| Data services | Amazon DynamoDB | On-demand capacity. Reads 50 million RRU; writes 100,000 WRU; Global Tables: 1 replica region. Storage under the free 25 GB. Committed estimate: Database Savings Plans. |
| Backup and S3 | Amazon S3 | S3 Standard 1,500 GB, Glacier Instant Retrieval 1,500 GB, Glacier Flexible Retrieval 4,500 GB, Glacier Deep Archive 6,000 GB. Replication: S3 Replication Time Control, 6,500 GB. |
| Backup and S3 | AWS Backup | Amazon Aurora backup, warm storage 12,900 GB. |
| Logs and security | Amazon CloudWatch | Logs: Standard ingestion 660 GB, storage 8,030 GB (365-day retention, 11 clusters of both regions). Vended logs delivered to S3: 800 GB. |
| Logs and security | Amazon Data Firehose | Direct PUT, 360 GB ingested (EKS control-plane logs to the log archive). |
| Logs and security | AWS Key Management Service | 40 customer managed keys, 20 million symmetric requests. |
| Logs and security | AWS Secrets Manager | 40 secrets (with the us-east-1 replicas). |
| Logs and security | Amazon GuardDuty | RDS Protection: 520 vCPU (both regions). EKS Runtime Monitoring: 624 vCPU (both regions). Foundational: 300 GB of CloudTrail, VPC flow and DNS logs. |
| Logs and security | AWS Security Hub | 40,000 security checks (2 regions). |
| Logs and security | AWS Config | 50,000 configuration items, 100,000 conformance pack evaluations. |
| Logs and security | Amazon Inspector | EC2 scanning: 84 instances on average (both regions). |

## Prod, us-east-1 and global

| Group | Region | Calculator service | Fields and values |
|---|---|---|---|
| Aurora | us-east-1 | Amazon Aurora PostgreSQL-Compatible DB | Hot standby, one instance per global secondary at the writer class. Entry 1, Aurora I/O-Optimized: `db.r7g.12xlarge` x 4, storage 8,000 GB. Entry 2, Aurora Standard: `db.r7g.2xlarge` x 1 (spare), `db.r7g.4xlarge` x 1 (locker), storage 600 GB. Global Database replicated write I/Os: 1,550 million. Committed estimate: Database Savings Plans, 1 year, No Upfront. |
| Aurora | us-east-1 | Amazon RDS Proxy | vCPU of the target instances: 216 (4 x 48, spare 8, locker 16). |
| MemoryDB | us-east-1 | Amazon MemoryDB | Node type `db.r7g.xlarge`. Shards 9, replicas per shard 2, giving 27 nodes. Pricing: OnDemand (committed: Reserved, 1 year, No Upfront). No data written while Frankfurt serves. |
| EKS | us-east-1 | Amazon EKS | Number of clusters 5 (4 cells, spare), standard support. |
| EKS nodes | us-east-1 | Amazon EC2 | m7g.large x 15, m7g.4xlarge x 12, m7g.2xlarge x 6, m7g.xlarge x 3, Linux, Shared, Constant usage (committed: Compute Savings Plans as in eu-central-1). EBS gp3: 36 nodes x 84 GB. |
| Network | us-east-1 | Elastic Load Balancing | Network Load Balancer x 1, 1 LCU on average. |
| Network | us-east-1 | Amazon VPC, AWS Network Firewall | 27 endpoint ENIs; 3 public IPv4; 2 Transit Gateway attachments; 3 firewall endpoints. |
| Backup and S3 | us-east-1 | Amazon S3, AWS Backup | S3 Glacier Instant Retrieval 6,500 GB; Aurora backup warm storage 12,900 GB. |
| Edge | us-east-1 | Amazon CloudFront | Europe: 50 GB data out, 5 million HTTPS requests. |
| Edge | us-east-1 | AWS WAF | 1 web ACL, 10 rules, 5 million requests. |
| Network | global | AWS Global Accelerator | 1 standard accelerator, 730 hours; 8,710 GB Europe to Europe in the dominant direction. |
| Edge | global | Amazon Route 53 | 1 hosted zone. |

## Stage

Enter from [stage.md](stage.md), with `size_window = "scheduled"`:

- Aurora (eu-central-1): I/O-Optimized `db.r7g.large` x 4 (cell writers, no readers), storage 800 GB; Standard `db.r7g.large` x 2 (spare, locker), storage 100 GB; RDS Proxy 12 vCPU; backup 900 GB. No standby region: stage runs in eu-central-1 alone.
- MemoryDB: `db.t4g.small`, 5 clusters x 1 shard x 3 nodes (15 nodes); data written 200 GB.
- EKS: 6 clusters. EC2 On-Demand, 730 hours: m7g.large x 18, m7g.2xlarge x 6 (5 cell workers pools, 1 analytics workers pool). EC2 On-Demand, 260.71 hours (working window): m7g.xlarge x 3 (cde). EC2 Spot: m7g.4xlarge x 8 and m7g.2xlarge x 1 (payments, 260.71 hours), r7g.2xlarge x 2 (730 hours). gp3 38 x 84 GB plus 2,000 GB.
- MSK: `kafka.m7g.large` x 3, 500 GB each.
- Network: 30 endpoint ENIs (27 interface endpoints, 3 of the log domain endpoint), 3 firewall endpoints, 3 public IPv4 and 2 Transit Gateway attachments in eu-central-1; 1 NLB; 1 accelerator. us-east-1 holds only the panel edge.
- Traffic: internet out 400 GB, firewall 200 GB, Transit Gateway 400 GB, cross-AZ 1,000 GB, endpoint data 500 GB, NLB 2 LCU.
- S3 Standard 100 GB, Glacier IR 100 GB, Glacier Flexible 300 GB, Deep Archive 300 GB, no cross-region replication; Backup 1,300 GB in eu-central-1.
- CloudWatch Logs: 180 GB ingested, 2,190 GB stored; vended 150 GB. Firehose: 180 GB.
- A `prod-size` window is entered as the prod eu-central-1 tables for the booked hours, without the commitments.

## Dev

Enter from [dev.md](dev.md):

- Aurora (eu-central-1): I/O-Optimized `db.r7g.large` x 1 (cell-0), storage 20 GB; Standard `db.r7g.large` x 2 (spare, locker), storage 40 GB; 260.71 instance hours a month (`aurora-schedule`); RDS Proxy 6 vCPU. No recovery regions.
- MemoryDB: `db.t4g.small`, 2 clusters x 1 shard x 3 nodes (6 nodes).
- EKS: 3 clusters. EC2 On-Demand: m7g.large x 9 and m7g.xlarge x 3 for 730 hours, and m7g.xlarge x 1 (cde) for 260.71 hours. EC2 Spot: m7g.2xlarge x 2 (payments) for 260.71 hours and r7g.xlarge x 1 for 730 hours. gp3 16 x 84 GB plus 100 GB.
- MSK: `kafka.m7g.large` x 3, 100 GB each.
- Network: 30 endpoint ENIs in eu-central-1 (27 interface endpoints, 3 of the log domain endpoint); 1 firewall endpoint, 3 public IPv4 and 2 Transit Gateway attachments; 1 NLB; 1 accelerator.
- CloudWatch Logs: 30 GB ingested, 30-day retention. Firehose: 30 GB.

## Shared services, central observability, organization

| Estimate | Calculator service | Fields and values |
|---|---|---|
| pay-shared-services | Amazon EC2 | Spot, 260 hours a month: c7gd.4xlarge x 2, m7g.2xlarge x 2, m7g.large x 2, c7g.2xlarge x 2; gp3 100 GB. |
| pay-shared-services | Amazon ECR, Amazon S3, Amazon VPC | ECR 1,300 GB; S3 Standard 1,000 GB; 27 interface endpoint ENIs. |
| pay-shared-services | AWS Private CA, AWS Secrets Manager, AWS KMS, Amazon Route 53 | 1 CA in short-lived certificate mode; 15 secrets; 6 keys; 1 hosted zone. |
| pay-central-observability | Amazon EKS, Amazon EC2 | 1 cluster. m7g.large x 3 and r7g.2xlarge x 4, with Compute Savings Plans 1 year No upfront in the committed view; m7g.2xlarge x 2 on Spot. gp3 3,252 GB (with the Logstash queues), extra throughput 375 MB/s. |
| pay-central-observability | Amazon OpenSearch Service | Domain `pay-shared-euc1-logs`: data nodes `r7g.xlarge.search` x 6, gp3 600 GB per node; dedicated master `m7g.large.search` x 3; UltraWarm `ultrawarm1.medium.search` x 8, managed storage 10,740 GB. Pricing: OnDemand (committed: Database Savings Plans, 1 year, No Upfront for data and master nodes). OpenSearch Ingestion: 2 pipelines x 1 OCU, 730 hours. |
| pay-central-observability | Amazon S3, Amazon VPC, AWS Data Transfer | S3 Standard 800 GB; Transit Gateway 5,000 GB processed; intra-region 3,000 GB. |
| pay-organization | Amazon CloudWatch, Amazon S3, AWS KMS | 50 GB log ingestion; S3 Standard 6,210 GB and Glacier Flexible 18,630 GB; 3 keys. |
| pay-organization | AWS Security Hub, Amazon Macie, Amazon GuardDuty, AWS Config | 40,000 checks; 60 buckets and 20 GB discovery; 50 GB foundational analysis; 10,000 configuration items. |

## Check

Each saved estimate must match its expected total above within a few percent (committed column where Spot is entered); the Spot discount and the NAT waiver explain the rest.
