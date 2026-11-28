# Cost of central observability

Monthly cost at the target load, from the AWS Price List (eu-central-1, us-east-1, global). Method and assumptions: [README.md](README.md).

- Cluster: `infra/live/shared-services/eu-central-1/central/` (`central_cpu_limits`, `central_spot_pools = []`).
- Workloads: VictoriaMetrics, Logstash, Tempo, Sentry, Grafana and Alertmanager from `deploy/platform/*/values.yaml`; object stores from `infra/modules/observability-storage`.
- Central log domain `pay-shared-euc1-logs` (`logs_domain` in `infra/live/shared-services/env.hcl`): 6 hot data nodes, 3 dedicated masters, 8 UltraWarm nodes. Volume from the same file: application logs about 30 GB a day, audit about 30 GB a day. UltraWarm storage is priced at full retention (application logs days 8-30, audit days 31-365); in the first year it grows towards that value. OpenSearch Ingestion is priced at the minimum of 1 OCU per pipeline.
- Retention: metrics 13 months, application logs 30 days (7 hot), audit trail 365 days (30 hot), traces 14 days, Sentry events 30 days (file store 90 days).
- The environment VPC endpoints of the log domain are in the [prod](prod.md), [stage](stage.md) and [dev](dev.md) files.
- The workers pool uses Spot first (`infra/modules/karpenter`), so its committed column applies the Spot planning rate.
- Committed column: Compute Savings Plan 1 year no upfront on 80% of the remaining EC2; Database Savings Plan 1 year no upfront on the data and master nodes of the log domain (UltraWarm and OpenSearch Ingestion have no commitment).

Total: **8,021 USD/month on demand**, **6,858 USD/month committed**.

## By group

| Group | On-demand (USD/month) | Committed (USD/month) |
|---|---:|---:|
| Logs | 5,156.06 | 4,709.30 |
| EKS nodes | 2,294.10 | 1,578.11 |
| Storage | 337.90 | 337.90 |
| Network | 160.00 | 160.00 |
| EKS | 73.00 | 73.00 |
| **Total** | **8,021.06** | **6,858.31** |

## Line items

Hours are per month (730 for 24/7). Usage lines have no hours: quantity times unit price.

| Group | Region | Service | Resource | Configuration | Quantity | Hours | Unit | Unit price (USD) | Monthly on-demand (USD) | Pricing model | Monthly committed (USD) |
|---|---|---|---|---|---:|---:|---|---:|---:|---|---:|
| EKS | eu-central-1 | Amazon EKS | control plane | central cluster | 1 | 730 | cluster-hour | 0.1 | 73.00 | on-demand | 73.00 |
| EKS nodes | eu-central-1 | Amazon EC2 | bootstrap node group | m7g.large, Linux, shared tenancy | 3 | 730 | instance-hour | 0.0978 | 214.18 | Compute SP 1yr no upfront, 80% covered | 173.36 |
| EKS nodes | eu-central-1 | Amazon EC2 | stateful pool: VictoriaMetrics, Tempo, Logstash, Sentry stores | r7g.2xlarge, Linux, shared tenancy | 4 | 730 | instance-hour | 0.5168 | 1,509.06 | Compute SP 1yr no upfront, 80% covered | 1,176.41 |
| EKS nodes | eu-central-1 | Amazon EC2 | workers pool: Grafana, Alertmanager, vmalert, Sentry web and workers | m7g.2xlarge, Linux, Spot | 2 | 730 | instance-hour | 0.391 | 570.86 | Spot at 40% of on-demand | 228.34 |
| Storage | eu-central-1 | Amazon EBS | node volumes | gp3, 9 nodes x 84 GB | 756 |  | GB-month | 0.0952 | 71.97 | on-demand | 71.97 |
| Storage | eu-central-1 | Amazon EBS | persistent volumes | vmstorage 3 x 500, Sentry ClickHouse 3 x 200, Kafka, Postgres, WAL | 2,400 |  | GB-month | 0.0952 | 228.48 | on-demand | 228.48 |
| Storage | eu-central-1 | Amazon EBS | vmstorage throughput above 125 MB/s | 3 volumes x 125 MB/s | 0.3662 |  | GiBps-month | 48.7424 | 17.85 | on-demand | 17.85 |
| Storage | eu-central-1 | Amazon S3 | Tempo blocks | 14-day retention, tail sampling | 300 |  | GB-month | 0.0245 | 7.35 | on-demand | 7.35 |
| Storage | eu-central-1 | Amazon S3 | Sentry files and vmbackup | Intelligent-Tiering, frequent tier | 500 |  | GB-month | 0.0245 | 12.25 | on-demand | 12.25 |
| Logs | eu-central-1 | Amazon OpenSearch Service | pay-shared-euc1-logs data nodes | r7g.xlarge.search, 3 AZ | 6 | 730 | instance-hour | 0.429 | 1,879.02 | Database SP 1yr no upfront | 1,503.22 |
| Logs | eu-central-1 | Amazon OpenSearch Service | pay-shared-euc1-logs dedicated masters | m7g.large.search | 3 | 730 | instance-hour | 0.162 | 354.78 | Database SP 1yr no upfront | 283.82 |
| Logs | eu-central-1 | Amazon OpenSearch Service | pay-shared-euc1-logs UltraWarm nodes | ultrawarm1.medium.search | 8 | 730 | instance-hour | 0.284 | 1,658.56 | on-demand | 1,658.56 |
| Logs | eu-central-1 | Amazon OpenSearch Service | pay-shared-euc1-logs data node storage | gp3, 6 x 600 GB | 3,600 |  | GB-month | 0.1452 | 522.72 | on-demand | 522.72 |
| Logs | eu-central-1 | Amazon OpenSearch Service | pay-shared-euc1-logs UltraWarm managed storage | application logs days 8-30, audit days 31-365 | 10,740 |  | GB-month | 0.026 | 279.24 | on-demand | 279.24 |
| Logs | eu-central-1 | Amazon OpenSearch Service | OpenSearch Ingestion, audit pipelines | 2 pipelines at the minimum of 1 OCU each (up to 4) | 2 | 730 | OCU-hour | 0.31 | 452.60 | on-demand | 452.60 |
| Logs | eu-central-1 | Amazon EBS | Logstash persistent queues | gp3, 3 x 32 GB | 96 |  | GB-month | 0.0952 | 9.14 | on-demand | 9.14 |
| Network | eu-central-1 | AWS Transit Gateway | telemetry from the environments | metrics, logs, traces | 5,000 |  | GB | 0.02 | 100.00 | on-demand | 100.00 |
| Network | eu-central-1 | AWS Data Transfer | cross-AZ inside the cluster | replication of VictoriaMetrics and Tempo, Logstash to OpenSearch | 3,000 |  | GB | 0.02 | 60.00 | on-demand | 60.00 |
| **Total** | | | | | | | | | **8,021.06** | | **6,858.31** |
