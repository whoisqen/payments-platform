# observability-storage

Object stores of the central observability cluster (account shared-services, outside the CDE) and the Pod Identity roles that reach them.

- Buckets `<prefix>-shared-services-<region-short>-<component>`: `loki` (30 days), `tempo` (14 days), `sentry` (90 days, file store). Override `buckets` to change retention or the service account.
- SSE-KMS with the shared key, public access blocked, TLS only, versioning (replaced versions expire after `noncurrent_retention_days`), multipart uploads aborted after 7 days.
- One role `<bucket>-pod` per bucket with the permissions boundary, assumed by `monitoring/loki`, `monitoring/tempo` and `monitoring/sentry` through `aws_eks_pod_identity_association` on the central cluster.
- Policy: list the one bucket; get, put, delete and multipart actions on its objects; `kms:Decrypt` and `kms:GenerateDataKey` on the key, limited to the bucket by the S3 encryption context. No wildcard actions or resources.
- Outputs: `bucket_names`, `bucket_arns`, `role_arns` (maps by component).
