# permissions-boundary

IAM policy `workload-boundary` of one account: the permissions boundary every workload, cluster and CI role attaches.
It caps rights (no IAM users, access keys or login profiles, no Organizations or account changes), denies edits and removal of the boundary,
denies `iam:CreateRole` without this boundary and denies stopping CloudTrail, Config or GuardDuty.
Shared-services gets it from `infra/bootstrap` (its CI roles need it before any state exists); dev, stage and prod from `live/<env>/eu-central-1/permissions-boundary`.
Required: `account_id`, `tags`. Test: `terraform init -backend=false && terraform test`.
