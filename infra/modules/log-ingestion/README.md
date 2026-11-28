# log-ingestion

Writers of the central log domain (shared-services).

- `<prefix>-shared-services-<region-short>-logstash`: IRSA role of `monitoring/logstash` on the central cluster (`sub` and `aud` pinned), `es:ESHttpPost`, `ESHttpPut`, `ESHttpGet` on the domain; Logstash writes `logs-app-<env>`. Pod Identity readers: `<...>-os-exporter` (`monitoring/opensearch-exporter`, `es:ESHttpGet`) and `<...>-grafana` (`monitoring/grafana`, `es:ESHttpGet` and `ESHttpPost`).
- OpenSearch Ingestion pipelines `<prefix>-audit-cloudtrail` and `<prefix>-audit-eks` read the objects that the log-archive bucket announces on the queues `<...>-audit-cloudtrail` and `<...>-audit-eks` (S3 event notifications, so only new objects) and write `logs-audit`: CloudTrail `Records`, and the `kube-apiserver-audit` streams of the EKS export (other control-plane streams are dropped).
- Pipeline role `<...>-audit-ingest`: the two queues, list and get on the two prefixes, `kms:Decrypt` through S3 in the log-archive account, HTTP on the domain. The log-archive module must admit it (`ingest_reader_principal_arns`) and notify the queues (`ingest_notifications`).
- Pipelines run in the private subnets with the domain client security group; buffers encrypted with `kms_key_arn`; logs in `/aws/vendedlogs/OpenSearchIngestion/...` with `log_retention_days`.
- Every role carries the permissions boundary. The fine-grained access mappings of both roles are in `opensearch-indices`.
