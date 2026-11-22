# s3-backup

Versioned, KMS-encrypted bucket with Object Lock on every copy, for object backups, audit logs, the event archive and Terraform state (D5, D7).

- `region_role = working`: source bucket, locked destination buckets in `recovery_regions` and one replication rule per destination with Replication Time Control (15 minutes) plus a latency alarm.
- `region_role = recovery`: one locked bucket in the provider region, no replication.
- Lifecycle for `lifecycle_prefixes`: Glacier Instant Retrieval at 7 days, Glacier at 14, expiry at 35; `archive/monthly/` goes to Deep Archive and expires after 7 years.
- Infrequent Access classes need 30 days in STANDARD, so they are not used; the archive needs its own retention set at upload.
- One module owns the bucket policy; add statements through `bucket_policy_statements`. Bucket names must be globally unique.
