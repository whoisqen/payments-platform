# vpc

Three-AZ VPC named `pay-<env>-<region-short>-<component>` with public, private and data tiers, one route table per AZ
for private and data (and public with `public_route_table_per_az`, egress VPC), a locked default security group and no internet gateway unless `enable_internet_gateway` is set.
The private tier reaches the internet only through `egress_transit_gateway_id` (with `enable_egress_route`) (network account, Network Firewall).
The optional `untrusted` tier (pull request runners) has its own route tables: only the transit gateway (Network Firewall CI allowlist) and the S3 gateway endpoint.
Gateway endpoints (S3, DynamoDB) and interface endpoints (ECR, STS, KMS, Secrets Manager, SSM, logs) keep AWS API traffic private.
Flow logs go to the S3 bucket `flow_logs_bucket_arn` in parquet.
The standby region uses the same module (`region = us-east-1`, its own CIDR from config/platform.yaml).
Test: `terraform init -backend=false && terraform test`.
