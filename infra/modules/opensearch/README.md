# opensearch

The central log domain (shared-services): 3 dedicated masters, hot data nodes over three AZs, UltraWarm, VPC-only; `domain_name` sets the name (3-28 characters, a precondition enforces it).

- Encryption at rest with a KMS key, node-to-node TLS, TLS 1.2 PFS minimum, fine-grained access control with an IAM master role and no internal user database.
- `custom_endpoint`: the domain and Dashboards answer on the admin host with an ACM certificate from the private CA. `saml`: Dashboards sign-in through Okta, the `groups` attribute becomes the backend roles; the access policy then admits `*` and fine-grained access control decides.
- Security groups: the domain group admits 443 from `client_security_group_ids`, `client_cidr_blocks` and the module's own client group (output `client_security_group_id`, for ingestion pipelines).
- Error, search slow and index slow logs go to `/aws/opensearch/<name>`, encrypted with `logs_kms_key_arn`, retained `log_retention_days`, with a resource policy scoped to the account.
- `endpoint_account_ids` may create an OpenSearch-managed VPC endpoint of the domain in their own VPC (`opensearch-endpoint`).
- `snapshot_bucket_arn` adds a Snapshot Management role. Small domains: `availability_zone_count = 1`, `dedicated_master_count = 0`, `warm_node_count = 0`. Index layer: `opensearch-indices`.
