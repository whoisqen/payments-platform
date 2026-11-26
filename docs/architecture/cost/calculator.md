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
| pay-prod (on demand) | 161,487 | paste after saving |
| pay-prod-committed | 129,881 | paste after saving |
| pay-stage | 137,441 with Spot pools (148,093 all on demand) | paste after saving |
| pay-dev | 9,259 with Spot pools (10,229 all on demand) | paste after saving |
| pay-shared-services | 868 with Spot runners (1,385 all on demand) | paste after saving |
| pay-central-observability | 2,887 | paste after saving |
| pay-organization | 378 | paste after saving |

The calculator applies its own historical Spot discount instead of the 40% planning rate, so Spot lines differ a little. It also does not apply the NAT waiver behind Network Firewall, so NAT gateways are left out of the entry.

## Prod, eu-central-1

| Group | Calculator service | Fields and values |
|---|---|---|
| Aurora | Amazon Aurora PostgreSQL-Compatible DB | Cluster configuration: Aurora I/O-Optimized. Add 3 instance rows: `db.r7g.12xlarge` x 6 (4 cell writers, spare, locker), `db.r7g.4xlarge` x 6 (readers). Utilization 100%. Pricing model: OnDemand (committed estimate: Reserved, 1 year, No Upfront). Storage: 8,600 GB. Backup storage: 8,600 GB above the free allowance. |
| Aurora | Amazon RDS Proxy | Database engine: Aurora PostgreSQL. vCPU of the target instances: 384 (6 x 64). |
| MemoryDB | Amazon MemoryDB | Node type `db.r7g.xlarge`. Shards 10 (2 per cell x 5), replicas per shard 2, giving 30 nodes. Pricing: OnDemand (committed: Reserved, 1 year, No Upfront). Data written: 6,220 GB per month. |
| EKS | Amazon EKS | Number of clusters 6, standard support. |
| EKS nodes | Amazon EC2 | One row per line of [prod.md](prod.md) "EKS nodes": OS Linux, tenancy Shared, workload Constant usage. Instances: m7g.large x 21, m7g.4xlarge x 15, m7g.2xlarge x 7, m7g.xlarge x 3, r7g.2xlarge x 8. Pricing strategy: On-Demand (committed: Compute Savings Plans, 1 year, No upfront, then reduce coverage to 80%). EBS: General Purpose SSD (gp3), 54 nodes x 84 GB plus 8,000 GB for ClickHouse, default IOPS and throughput. |
| Analytics | Amazon MSK | Provisioned. Broker `kafka.m7g.xlarge`, 9 brokers, storage 2,000 GB per broker. |
| Analytics | Amazon OpenSearch Service | Data nodes `r7g.xlarge.search` x 6, gp3 1,024 GB per node. Dedicated master `m7g.large.search` x 3. UltraWarm `ultrawarm1.medium.search` x 2, managed storage 1,000 GB. Pricing: OnDemand (committed: Reserved, 1 year, No Upfront for data and master nodes). |
| Network | Amazon VPC | Interface endpoints: 9 endpoints x 3 AZ (27 ENIs), 2,000 GB processed. Public IPv4: 3 in-use addresses. Transit Gateway: 2 VPC attachments, 20,740 GB processed. |
| Network | AWS Network Firewall | Firewall endpoints 3, data processed 10,370 GB. |
| Network | Elastic Load Balancing | Network Load Balancer x 1, 10 LCU on average (enter as processed bytes of 10 GB per hour, or new connections that produce 10 LCU). |
| Data transfer | AWS Data Transfer | Outbound to the internet: 19,080 GB. Inter-region outbound to us-east-1: 6,200 (Aurora) + 6,500 (S3) + 6,200 (Backup) GB; to us-east-2: the same three values. Intra-region (cross-AZ): 15,350 GB. |
| Data services | Amazon DynamoDB | On-demand capacity. Reads 50 million RRU; writes 100,000 WRU; Global Tables: 2 replica regions. Storage under the free 25 GB. |
| Backup and S3 | Amazon S3 | S3 Standard 1,500 GB, Glacier Instant Retrieval 1,500 GB, Glacier Flexible Retrieval 4,500 GB, Glacier Deep Archive 6,000 GB. Replication: S3 Replication Time Control, 13,000 GB. |
| Backup and S3 | AWS Backup | Amazon Aurora backup, warm storage 12,900 GB. |
| Logs and security | Amazon CloudWatch | Logs: Standard ingestion 660 GB, storage 8,030 GB (365-day retention). Vended logs delivered to S3: 800 GB. |
| Logs and security | AWS Key Management Service | 40 customer managed keys, 20 million symmetric requests. |
| Logs and security | AWS Secrets Manager | 60 secrets. |
| Logs and security | Amazon GuardDuty | RDS Protection: 480 vCPU. EKS Runtime Monitoring: 656 vCPU. Foundational: 300 GB of CloudTrail, VPC flow and DNS logs. |
| Logs and security | AWS Security Hub | 60,000 security checks. |
| Logs and security | AWS Config | 50,000 configuration items, 100,000 conformance pack evaluations. |
| Logs and security | Amazon Inspector | EC2 scanning: 87 instances on average (both regions). |

## Prod, us-east-1, us-east-2 and global

| Group | Region | Calculator service | Fields and values |
|---|---|---|---|
| Aurora | us-east-1 | Amazon Aurora PostgreSQL-Compatible DB | I/O-Optimized. `db.r7g.4xlarge` x 6 (one reader per secondary), Reserved 1 year No Upfront in the committed estimate. Storage 8,600 GB. Global Database replicated write I/Os: 1,550 million. |
| Aurora | us-east-2 | Amazon Aurora PostgreSQL-Compatible DB | I/O-Optimized, no instances. Storage 8,600 GB. Replicated write I/Os: 1,550 million. |
| MemoryDB | us-east-1 | Amazon MemoryDB | `db.r7g.xlarge`, 10 shards, 2 replicas per shard (30 nodes). No data written. |
| EKS | us-east-1 | Amazon EKS | 5 clusters. |
| EKS nodes | us-east-1 | Amazon EC2 | m7g.large x 15, m7g.4xlarge x 10, m7g.2xlarge x 5, m7g.xlarge x 3; gp3 33 x 84 GB. |
| Network | us-east-1 | Amazon VPC, AWS Network Firewall, Elastic Load Balancing | 27 endpoint ENIs; 3 public IPv4; 2 Transit Gateway attachments; 3 firewall endpoints; 1 NLB with 1 LCU. |
| Network | us-east-2 | Amazon VPC | 27 endpoint ENIs. |
| Backup and S3 | us-east-1, us-east-2 | Amazon S3, AWS Backup | S3 Glacier Instant Retrieval 6,500 GB each; Aurora backup warm storage 12,900 GB each. |
| Edge | us-east-1 | Amazon CloudFront | Europe: 50 GB data out, 5 million HTTPS requests. |
| Edge | us-east-1 | AWS WAF | 1 web ACL, 10 rules, 5 million requests. |
| Network | global | AWS Global Accelerator | 1 standard accelerator, 730 hours; 8,710 GB Europe to Europe in the dominant direction. |
| Edge | global | Amazon Route 53 | 1 hosted zone. |

## Stage

Enter the prod tables again with these differences (values in [stage.md](stage.md)):

- EC2 rows of the payments and stateful pools: pricing strategy Spot. Everything else stays On-Demand; there are no reservations.
- Aurora storage 900 GB per region, backup 900 GB; replicated write I/Os 50 million per region.
- MemoryDB data written 200 GB. MSK, OpenSearch, EKS and node counts are the prod values.
- Traffic: internet out 400 GB, firewall 200 GB, Transit Gateway 400 GB, cross-AZ 1,000 GB, endpoint data 500 GB, NLB 2 LCU.
- S3 Standard 100 GB, Glacier IR 100 GB, Glacier Flexible 300 GB, Deep Archive 300 GB, RTC 600 GB; Backup 1,300 GB per region.
- CloudWatch Logs: 330 GB ingested, 4,015 GB stored; vended 150 GB.

## Dev

Enter from [dev.md](dev.md):

- Aurora (eu-central-1): I/O-Optimized, `db.r7g.large` x 6, storage 120 GB; RDS Proxy 12 vCPU. us-east-1 and us-east-2: storage 120 GB each, no instances.
- MemoryDB: `db.t4g.small`, 5 shards, 2 replicas (15 nodes).
- EKS: 6 clusters. EC2: m7g.large x 18 and m7g.xlarge x 7 On-Demand; m7g.2xlarge x 5 and r7g.xlarge x 1 Spot; gp3 31 x 84 GB plus 100 GB.
- MSK: `kafka.m7g.large` x 3, 100 GB each. OpenSearch: `m7g.medium.search` x 1, 20 GB gp3, no masters.
- Network: 27 endpoint ENIs in each of the three regions; 3 firewall endpoints, 3 public IPv4 and 2 Transit Gateway attachments in eu-central-1; 1 NLB; 1 accelerator.
- CloudWatch Logs: 60 GB ingested, 30-day retention.

## Shared services, central observability, organization

| Estimate | Calculator service | Fields and values |
|---|---|---|
| pay-shared-services | Amazon EC2 | Spot, 260 hours a month: c7gd.4xlarge x 2, m7g.2xlarge x 2, m7g.large x 2, c7g.2xlarge x 2; gp3 100 GB. |
| pay-shared-services | Amazon ECR, Amazon S3, Amazon VPC | ECR 1,900 GB; S3 Standard 1,000 GB; 27 interface endpoint ENIs. |
| pay-shared-services | AWS Private CA, AWS Secrets Manager, AWS KMS, Amazon Route 53 | 1 CA in short-lived certificate mode; 15 secrets; 6 keys; 1 hosted zone. |
| pay-central-observability | Amazon EKS, Amazon EC2 | 1 cluster. m7g.large x 3, r7g.2xlarge x 4, m7g.2xlarge x 2, Compute Savings Plans 1 year No upfront in the committed view. gp3 3,156 GB, extra throughput 375 MB/s. |
| pay-central-observability | Amazon S3, Amazon VPC, AWS Data Transfer | S3 Standard 1,700 GB; Transit Gateway 5,000 GB processed; intra-region 3,000 GB. |
| pay-organization | Amazon CloudWatch, Amazon S3, AWS KMS | 50 GB log ingestion; S3 Standard 4,500 GB and Glacier Flexible 13,500 GB; 3 keys. |
| pay-organization | AWS Security Hub, Amazon Macie, Amazon GuardDuty, AWS Config | 60,000 checks; 60 buckets and 20 GB discovery; 50 GB foundational analysis; 10,000 configuration items. |

## Check

Each saved estimate must match its expected total above within a few percent (committed column where Spot is entered); the Spot discount and the NAT waiver explain the rest.
