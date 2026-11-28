# opensearch-endpoint

OpenSearch-managed VPC endpoint of the central log domain (shared-services) in the VPC of one environment, so the admin agent of that environment reaches its logs without a route between the accounts.

- The domain owner authorizes the account first (`opensearch` input `endpoint_account_ids`); then this module creates the endpoint in `subnet_ids`.
- Security group `<prefix>-<env>-<region-short>-logs-endpoint`: 443 from `client_cidr_blocks` only.
- Access stays with the domain: its access policy and fine-grained access control (`logs_reader_<env>` reads only `logs-app-<env>`).
- Output `endpoint`: the host name for `opensearch.url` of `config/admin-agent.yaml`.
