# log-archive

Central, immutable log bucket of the organization in the log-archive account: organization trail, Config, VPC Flow Logs and EKS control-plane logs (PCI DSS 10.5.1).

- Object Lock COMPLIANCE `object_lock_days` (365), versioning, SSE-KMS with its own rotated key, BucketOwnerEnforced, public access blocked.
- Bucket policy: TLS only, deletes of objects, versions and the bucket denied to everyone, writes only for `cloudtrail.amazonaws.com` (`aws:SourceArn` = `trail_arn`), `config.amazonaws.com` and `delivery.logs.amazonaws.com` (`aws:SourceOrgID`) and organization roles named `*-log-export` (EKS Firehose, `aws:PrincipalOrgID`) under their own prefix.
- Lifecycle: Glacier after `glacier_after_days` (90), expiry after `expiration_days` (400, never before the lock ends).
- Server access logs go to `<name>-access-logs` (SSE-S3, no Object Lock: S3 cannot log into a bucket with default retention).
- `trail_arn` is built from the trail name, so this stack applies before the trail stack. Readers in the audit account come from `reader_principal_arns`; the central log ingestion role (`ingest_reader_principal_arns`) reads only `cloudtrail/` and `eks/`, notified through `ingest_notifications`.
