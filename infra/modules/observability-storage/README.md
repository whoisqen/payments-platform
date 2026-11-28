# observability-storage

Object stores of the central observability cluster (account shared-services, outside the CDE) and the Pod Identity roles that reach them.

- Buckets `<prefix>-shared-services-<region-short>-<component>`: `tempo` (14 days), `sentry` (90 days, file store), `vmbackup`; logs live in the central OpenSearch (`opensearch`), not here. Override `buckets` to change retention or the service account.
- SSE-KMS with the shared key, public access blocked, TLS only, versioning (replaced versions expire after `noncurrent_retention_days`), multipart uploads aborted after 1 day.
- One role `<bucket>-pod` per bucket with the permissions boundary, assumed by `monitoring/tempo`, `monitoring/sentry` and `victoria-metrics/vmbackup` through `aws_eks_pod_identity_association` on the central cluster.
- Policy: list the one bucket; get, put, delete and multipart actions on its objects; `kms:Decrypt` and `kms:GenerateDataKey` on the key, limited to the bucket by the S3 encryption context. No wildcard actions or resources.
- Tiering: a Standard-IA transition applies only when objects stay 30 days past it (IA bills 30 days minimum); Sentry and vmbackup use Intelligent-Tiering; vmbackup has no age expiry (incremental parts stay referenced).
- `yace` adds `<prefix>-shared-services-<region-short>-yace-pod` for `monitoring/yace`: CloudWatch reads and `tag:GetResources` (`*`, no resource scoping). Outputs: `bucket_names`, `bucket_arns`, `role_arns` (by component), `yace_role_arn`.
