# kms-set

Every KMS key of a region in one stack: calls `../kms` once per entry of `keys` (nothing is copied).
In the working region it creates multi-Region primaries; in a recovery region set `is_replica` and pass `primary_key_arns` from the Frankfurt stack to get replicas of the same purposes.
Required: `account_id`, `region`, `environment`, `keys`, `tags`.
Outputs: `key_arns`, `alias_names` by purpose.
Test: `terraform init -backend=false && terraform test` (mock provider).
