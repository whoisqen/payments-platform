# vpc

Three-AZ VPC named `pay-<env>-<region-short>-<component>` with public, private and data tiers, one route table per AZ
for private and data, a locked default security group and no internet gateway unless `enable_internet_gateway` is set.
The private tier reaches the internet only through `egress_transit_gateway_id` (with `enable_egress_route`) (network account, Network Firewall).
Gateway endpoints (S3, DynamoDB) and interface endpoints (ECR, STS, KMS, Secrets Manager, SSM, logs) keep AWS API traffic private.
Flow logs go to the S3 bucket `flow_logs_bucket_arn` in parquet.
Recovery regions use the same module (`region = us-east-1` or `us-east-2`, CIDRs 10.102.0.0/16 and 10.103.0.0/16); it creates no compute.
Test: `terraform init -backend=false && terraform test`.
