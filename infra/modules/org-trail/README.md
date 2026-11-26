# org-trail

Organization CloudTrail in the management account: every account, every region, into the log-archive bucket.

- Multi-region, global service events, log file validation, SSE-KMS with the log-archive key (`s3_kms_key_arn`), prefix `s3_key_prefix`.
- A copy goes to CloudWatch Logs (`/aws/cloudtrail/<name>`, own rotated key, `log_retention_days`) for metric filters and alarms.
- Advanced selectors: all management events, plus S3 object-level events of buckets whose names start with `cde_s3_bucket_prefixes` (selectors cannot filter by account, so CDE buckets are matched by name).
- The trail name is fixed (`<prefix>-<env>-<region-short>-org-trail`); log-archive builds the ARN from it, so log-archive applies first.
- Prerequisite: trusted access for `cloudtrail.amazonaws.com` in the organization.
