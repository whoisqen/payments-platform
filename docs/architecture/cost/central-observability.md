# Cost of central observability

Monthly cost at the target load, from the AWS Price List (eu-central-1, us-east-1, global). Method and assumptions: [README.md](README.md).

- Cluster: `infra/live/shared-services/eu-central-1/central/` (`central_cpu_limits`, `central_spot_pools = []`).
- Workloads: VictoriaMetrics, Loki, Tempo, Sentry, Grafana and Alertmanager from `deploy/platform/*/values.yaml`; object stores from `infra/modules/observability-storage`.
- Retention: metrics 13 months, logs 30 days, traces 14 days, Sentry events 90 days.
- The workers pool uses Spot first (`infra/modules/karpenter`), so its committed column applies the Spot planning rate.
- Committed column: Compute Savings Plan 1 year no upfront on 80% of the remaining EC2.

Total: **2,887 USD/month on demand**, **2,171 USD/month committed**.

## By group

| Group | On-demand (USD/month) | Committed (USD/month) |
|---|---:|---:|
| EKS nodes | 2,294.10 | 1,578.11 |
| Storage | 359.95 | 359.95 |
| Network | 160.00 | 160.00 |
| EKS | 73.00 | 73.00 |
| **Total** | **2,887.05** | **2,171.06** |

## Line items

Hours are per month (730 for 24/7). Usage lines have no hours: quantity times unit price.

| Group | Region | Service | Resource | Configuration | Quantity | Hours | Unit | Unit price (USD) | Monthly on-demand (USD) | Pricing model | Monthly committed (USD) |
|---|---|---|---|---|---:|---:|---|---:|---:|---|---:|
| EKS | eu-central-1 | Amazon EKS | control plane | central cluster | 1 | 730 | cluster-hour | 0.1 | 73.00 | on-demand | 73.00 |
| EKS nodes | eu-central-1 | Amazon EC2 | bootstrap node group | m7g.large, Linux, shared tenancy | 3 | 730 | instance-hour | 0.0978 | 214.18 | Compute SP 1yr no upfront, 80% covered | 173.36 |
| EKS nodes | eu-central-1 | Amazon EC2 | stateful pool: VictoriaMetrics, Loki, Tempo, Sentry stores | r7g.2xlarge, Linux, shared tenancy | 4 | 730 | instance-hour | 0.5168 | 1,509.06 | Compute SP 1yr no upfront, 80% covered | 1,176.41 |
| EKS nodes | eu-central-1 | Amazon EC2 | workers pool: Grafana, Alertmanager, vmalert, Sentry web and workers | m7g.2xlarge, Linux, Spot | 2 | 730 | instance-hour | 0.391 | 570.86 | Spot at 40% of on-demand | 228.34 |
| Storage | eu-central-1 | Amazon EBS | node volumes | gp3, 9 nodes x 84 GB | 756 |  | GB-month | 0.0952 | 71.97 | on-demand | 71.97 |
| Storage | eu-central-1 | Amazon EBS | persistent volumes | vmstorage 3 x 500, Sentry ClickHouse 3 x 200, Kafka, Postgres, WAL | 2,400 |  | GB-month | 0.0952 | 228.48 | on-demand | 228.48 |
| Storage | eu-central-1 | Amazon EBS | vmstorage throughput above 125 MB/s | 3 volumes x 125 MB/s | 0.3662 |  | GiBps-month | 48.7424 | 17.85 | on-demand | 17.85 |
| Storage | eu-central-1 | Amazon S3 | Loki chunks | 30-day retention | 900 |  | GB-month | 0.0245 | 22.05 | on-demand | 22.05 |
| Storage | eu-central-1 | Amazon S3 | Tempo blocks | 14-day retention, tail sampling | 300 |  | GB-month | 0.0245 | 7.35 | on-demand | 7.35 |
| Storage | eu-central-1 | Amazon S3 | Sentry files and vmbackup | Intelligent-Tiering, frequent tier | 500 |  | GB-month | 0.0245 | 12.25 | on-demand | 12.25 |
| Network | eu-central-1 | AWS Transit Gateway | telemetry from the environments | metrics, logs, traces | 5,000 |  | GB | 0.02 | 100.00 | on-demand | 100.00 |
| Network | eu-central-1 | AWS Data Transfer | cross-AZ inside the cluster | replication of VictoriaMetrics, Loki, Tempo | 3,000 |  | GB | 0.02 | 60.00 | on-demand | 60.00 |
| **Total** | | | | | | | | | **2,887.05** | | **2,171.06** |
