# iam-workloads

EKS Pod Identity roles of one cell for router, locker, drainer, scheduler and external-secrets (section 23).
Trust is `pods.eks.amazonaws.com` limited to the account and the cluster ARN; every role has the workload boundary and the `deny_recovery_writes` policy of dynamodb-global.
Policies name resources and contain no `*`: MemoryDB users, `rds-db:connect` ARNs, the merchant table (read only), the locker key (locker only) and listed secrets.
Required: `region`, `environment`, `cell`, `account_id`, `cluster_name`, `cluster_arn`, `permissions_boundary_arn`, `deny_recovery_writes_policy_arn`, `memorydb`, two key ARNs, `dynamodb_table_arn`, `tags`.
Test: `terraform init -backend=false && terraform test` (mock provider).
