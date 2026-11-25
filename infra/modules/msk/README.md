# msk

MSK cluster of platform-prod: 9 brokers over three AZs, replication factor 3, `min.insync.replicas=2`, IAM auth only, TLS in transit and inside the cluster (D7).

- Topic auto-creation is off and unauthenticated access is off; topics come from the Kafka catalog.
- Not replicated across regions (D7): the S3 sink writes events to the archive bucket and Kafka is rebuilt from it.
- `sink_role_arn` is the MSK Connect role; `sink_bucket_policy_statements` goes into `bucket_policy_statements` of `s3-backup` so that one module owns the bucket policy.
- Broker logs go to `/aws/msk/<name>`, encrypted with `logs_kms_key_arn`; `enhanced_monitoring` is lowered to `DEFAULT` in dev.
- `producer_policy_arn` (connect, describe, write) is attached to producer roles; `client_settings` gives the producers bootstrap string, port 9098, `SASL_SSL` and `OAUTHBEARER`.
- No `region_role`: the cluster exists only in the working region.
