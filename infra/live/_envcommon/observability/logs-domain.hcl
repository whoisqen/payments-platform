locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
  cfg     = local.env_cfg.cfg
  size    = local.env_cfg.logs_domain
  # SAML of Dashboards: central.opensearch.saml (entity_id and the metadata XML of the Okta application); without it Dashboards has no SSO yet.
  saml = try(local.cfg.central.opensearch.saml, null)
}

terraform {
  source = "${get_repo_root()}/infra/modules//opensearch"
}

# The master role is the apply role of the account, so the index layer (opensearch-indices) signs as it.
# The environment accounts have no route to this VPC: each creates an OpenSearch-managed VPC endpoint (logs-endpoint) for its admin agent.
inputs = {
  domain_name             = local.cfg.central.opensearch.domain_name
  availability_zone_count = 3
  dedicated_master_count  = 3
  data_instance_type      = local.size.data_instance_type
  data_node_count         = local.size.data_node_count
  volume_size_gb          = local.size.volume_size_gb
  warm_instance_type      = local.size.warm_instance_type
  warm_node_count         = local.size.warm_node_count
  log_retention_days      = local.size.log_retention_days
  master_user_arn         = "arn:aws:iam::${local.env_cfg.account_id}:role/${local.cfg.naming.prefix}-${local.env_cfg.environment}-tf-exec"
  access_principal_arns   = ["*"]
  endpoint_account_ids    = [for env in ["dev", "stage", "prod"] : local.cfg.accounts[env]]
  saml = local.saml == null ? null : {
    entity_id           = local.saml.entity_id
    metadata_content    = local.saml.metadata
    master_backend_role = local.cfg.access.grafana_groups.admin
  }
  tags = {
    team        = "platform"
    owner       = local.env_cfg.owner
    pci-scope   = "out-of-scope"
    data-class  = "internal"
    backup-tier = "bronze"
  }
}
