# ecr

Repositories named `pay-<env>-<region-short>-<name>` with immutable tags, scan on push, KMS encryption and a lifecycle
policy (untagged expire after 14 days, last 50 tagged kept); enhanced continuous scanning is set registry-wide.
In the primary region set `replication_regions = ["us-east-1"]` (prod) for registry replication of every image.
In a recovery region run the module with no repositories and `create_replica_template` with `replica_kms_key_arn`: a creation template gives
the replicated repositories the same settings and the replica key. Replicas keep the primary region's repository names.
`pull_through_cache` rules with `credentials = true` (Docker Hub) get a secret `ecr-pullthroughcache/<prefix>`; the owner enters `username` and `accessToken`.
Test: `terraform init -backend=false && terraform test`.
