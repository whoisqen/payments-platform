# Cost of shared-services

Monthly cost at the target load, from the AWS Price List (eu-central-1, us-east-1, us-east-2, global). Method and assumptions: [README.md](README.md).

- Sizing: `infra/live/shared-services/env.hcl` (`ci_pools`), registry and access stacks in `infra/live/shared-services/eu-central-1/`.
- CI runners are Spot Auto Scaling groups; each pool keeps one warm instance 07:00-19:00 on weekdays (`ci-runners` schedule) and scales on CPU.
- Usage assumes two instances per pool on average during the 260 working hours of a month.
- The central observability cluster in this account has its own file: [central-observability.md](central-observability.md).

Total: **1,385 USD/month on demand**, **868 USD/month committed**.

## By group

| Group | On-demand (USD/month) | Committed (USD/month) |
|---|---:|---:|
| CI runners | 896.05 | 378.81 |
| Network | 236.52 | 236.52 |
| Registry | 190.00 | 190.00 |
| Access | 62.50 | 62.50 |
| **Total** | **1,385.07** | **867.83** |

## Line items

Hours are per month (730 for 24/7). Usage lines have no hours: quantity times unit price.

| Group | Region | Service | Resource | Configuration | Quantity | Hours | Unit | Unit price (USD) | Monthly on-demand (USD) | Pricing model | Monthly committed (USD) |
|---|---|---|---|---|---:|---:|---|---:|---:|---|---:|
| CI runners | eu-central-1 | Amazon EC2 | ci-build Auto Scaling group (2 average, working hours) | c7gd.4xlarge, Linux, Spot | 2 | 260 | instance-hour | 0.8392 | 436.38 | Spot at 40% of on-demand | 174.55 |
| CI runners | eu-central-1 | Amazon EC2 | ci-test Auto Scaling group (2 average, working hours) | m7g.2xlarge, Linux, Spot | 2 | 260 | instance-hour | 0.391 | 203.32 | Spot at 40% of on-demand | 81.33 |
| CI runners | eu-central-1 | Amazon EC2 | ci-light Auto Scaling group (2 average, working hours) | m7g.large, Linux, Spot | 2 | 260 | instance-hour | 0.0978 | 50.86 | Spot at 40% of on-demand | 20.34 |
| CI runners | eu-central-1 | Amazon EC2 | ci-pr Auto Scaling group (2 average, working hours) | c7g.2xlarge, Linux, Spot | 2 | 260 | instance-hour | 0.3298 | 171.50 | Spot at 40% of on-demand | 68.60 |
| CI runners | eu-central-1 | Amazon EBS | runner root volumes | gp3, 8 x 35 GB, working hours only | 99.70 |  | GB-month | 0.0952 | 9.49 | on-demand | 9.49 |
| CI runners | eu-central-1 | Amazon S3 | build cache bucket | 14-day expiry | 1,000 |  | GB-month | 0.0245 | 24.50 | on-demand | 24.50 |
| Registry | eu-central-1 | Amazon ECR | image storage, source registry |  | 500 |  | GB-month | 0.1 | 50.00 | on-demand | 50.00 |
| Registry | eu-central-1 | Amazon ECR | replicated images | 7 environment registries x 200 GB | 1,400 |  | GB-month | 0.1 | 140.00 | on-demand | 140.00 |
| Network | eu-central-1 | Amazon VPC | interface endpoints, shared-services VPC | 9 services x 3 AZ | 27 | 730 | endpoint-hour | 0.012 | 236.52 | on-demand | 236.52 |
| Access | eu-central-1 | AWS Private CA | admin gateway CA | short-lived certificate mode | 1 |  | CA-month | 50 | 50.00 | on-demand | 50.00 |
| Access | eu-central-1 | AWS Secrets Manager | secrets | central, Okta, runners | 15 |  | secret-month | 0.4 | 6.00 | on-demand | 6.00 |
| Access | eu-central-1 | AWS KMS | customer managed keys | ebs-nodes, shared, runner cache and secrets | 6 |  | key-month | 1 | 6.00 | on-demand | 6.00 |
| Access | global | Amazon Route 53 | private admin zone |  | 1 |  | zone-month | 0.5 | 0.50 | on-demand | 0.50 |
| **Total** | | | | | | | | | **1,385.07** | | **867.83** |
