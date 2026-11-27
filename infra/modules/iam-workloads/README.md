# iam-workloads

EKS Pod Identity roles of one cluster (a cell, or the locker, edge or control-center cluster): `services` (router, locker, drainer, scheduler) in `workload_namespace` (payments), external-secrets, and the optional `migrator` (section 23).
Trust is `pods.eks.amazonaws.com` limited to the account and the cluster ARN; every role has the workload boundary and the `deny_recovery_writes` policy of dynamodb-global.
Policies name resources and contain no `*`: MemoryDB users, `rds-db:connect` ARNs, the merchant table (read only), the locker key (locker only) and listed secrets.
`yace` (on by default) adds `<cell>-yace` for `monitoring/yace`: CloudWatch metric reads and `tag:GetResources`, the one policy with `*` (these APIs have no resource scoping).
`kafka_producer_policy_arn` (msk output) is attached to `kafka_producers` (router, scheduler): IAM auth and topic writes only.
`cell_kms_key_arn`: router encrypts and decrypts, drainer and scheduler decrypt. `migrator`: `rds-db:connect` as hs_migrator on the writer, the pre-migration AWS Backup job (start in the vault, pass the backup role), in its own policy because `DescribeBackupJob` has no resource scoping.
Required: `region`, `environment`, `cell`, `account_id`, `cluster_name`, `cluster_arn`, `permissions_boundary_arn`, `deny_recovery_writes_policy_arn`, `secrets_kms_key_arn`, `tags`.
Test: `terraform init -backend=false && terraform test` (mock provider).
