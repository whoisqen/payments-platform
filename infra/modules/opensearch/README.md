# opensearch

Log search domain of platform-prod: 3 dedicated masters, 6 data nodes over three AZs, UltraWarm for data older than 30 days, VPC-only.

- Encryption at rest with a KMS key, node-to-node TLS, TLS 1.2 PFS minimum, fine-grained access control without an internal user database.
- `snapshot_role_arn` lets the Snapshot Management policy (4-hourly, 14 days, kept in `deploy/platform/backup`) write to the `s3-backup` bucket.
- Domain names are limited to 28 characters; a precondition enforces it.
- Not replicated: logs also reach the S3 archive. No `region_role`: the domain exists only in the working region.
