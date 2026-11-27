# Cost of organization (management and security accounts)

Monthly cost at the target load, from the AWS Price List (eu-central-1, us-east-1, global). Method and assumptions: [README.md](README.md).

- Stacks: `infra/live/management/` and `infra/live/security/` (organization trail, Config, GuardDuty, Security Hub, Inspector, Macie, log-archive).
- Security services billed inside the workload accounts are in the environment files; this file holds the delegated-administrator and archive accounts.
- The log archive also holds the EKS control-plane logs that Firehose exports from prod, stage and dev: 570 GB a month.
- Shield Advanced is listed at zero: `security.shield_advanced_enabled` is not set in `config/platform.yaml`, so the organization runs Shield Standard.

Total: **421 USD/month on demand**, **421 USD/month committed**.

## By group

| Group | On-demand (USD/month) | Committed (USD/month) |
|---|---:|---:|
| Audit and logs | 262.10 | 262.10 |
| Security services | 158.42 | 158.42 |
| **Total** | **420.52** | **420.52** |

## Line items

Hours are per month (730 for 24/7). Usage lines have no hours: quantity times unit price.

| Group | Region | Service | Resource | Configuration | Quantity | Hours | Unit | Unit price (USD) | Monthly on-demand (USD) | Pricing model | Monthly committed (USD) |
|---|---|---|---|---|---:|---:|---|---:|---:|---|---:|
| Audit and logs | eu-central-1 | Amazon CloudWatch | organization trail log group | management events, ingestion | 50 |  | GB | 0.63 | 31.50 | on-demand | 31.50 |
| Audit and logs | eu-central-1 | Amazon S3 | log-archive, days 0-90, Standard | trails, flow logs, firewall logs, EKS control plane logs | 6,210 |  | GB-month | 0.0245 | 152.15 | on-demand | 152.15 |
| Audit and logs | eu-central-1 | Amazon S3 | log-archive, days 90-400, Glacier Flexible | Object Lock 365 days | 18,630 |  | GB-month | 0.00405 | 75.45 | on-demand | 75.45 |
| Audit and logs | eu-central-1 | AWS KMS | log-archive and trail keys |  | 3 |  | key-month | 1 | 3.00 | on-demand | 3.00 |
| Security services | eu-central-1 | AWS Security Hub | checks in management, security, shared-services | 2 regions | 40,000 |  | check | 0.001 | 40.00 | on-demand | 40.00 |
| Security services | eu-central-1 | Amazon Macie | bucket inventory | 60 buckets x 30 days | 1,800 |  | bucket-day | 0.003288 | 5.92 | on-demand | 5.92 |
| Security services | eu-central-1 | Amazon Macie | automated sensitive data discovery | sampled objects | 20 |  | GB | 1.25 | 25.00 | on-demand | 25.00 |
| Security services | eu-central-1 | Amazon GuardDuty | CloudTrail and DNS analysis, other accounts |  | 50 |  | GB | 1.15 | 57.50 | on-demand | 57.50 |
| Security services | eu-central-1 | AWS Config | configuration items, other accounts |  | 10,000 |  | item | 0.003 | 30.00 | on-demand | 30.00 |
| Security services | global | AWS Shield Advanced | subscription | not subscribed (security.shield_advanced_enabled unset) | 0 |  | month | 3000 | 0.00 | on-demand | 0.00 |
| **Total** | | | | | | | | | **420.52** | | **420.52** |
