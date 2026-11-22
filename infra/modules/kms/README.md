# kms

Customer managed symmetric key named `pay-<env>-<region-short>-<component>` with yearly rotation and a key policy that
separates administrators, users and AWS services.
The primary is a multi-Region key (`multi_region`); set `is_replica` and `primary_key_arn` to create a replica in a recovery region
(run the module with that region's provider alias). A replica has its own policy and follows the primary's rotation.
Required: `account_id`, `region`, `environment`, `component`, `tags` (no defaults for the five required tags).
Outputs: `key_arn`, `key_id`, `alias_name`.
Test: `terraform init -backend=false && terraform test` (mock provider, no credentials).
