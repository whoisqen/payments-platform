locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
  cfg     = local.env_cfg.cfg
}

terraform {
  source = "${get_repo_root()}/infra/modules//opensearch"
}

# The access policy admits the account; fine-grained access control maps IAM roles to OpenSearch roles, so IAM alone grants nothing.
inputs = {
  availability_zone_count = local.env_cfg.analytics.opensearch.availability_zone_count
  data_node_count         = local.env_cfg.analytics.opensearch.data_node_count
  data_instance_type      = local.env_cfg.analytics.opensearch.data_instance_type
  dedicated_master_count  = local.env_cfg.analytics.opensearch.dedicated_master_count
  warm_node_count         = local.env_cfg.analytics.opensearch.warm_node_count
  volume_size_gb          = local.env_cfg.analytics.opensearch.volume_size_gb
  master_user_arn         = try(local.cfg.analytics.opensearch_master_role_arn, "arn:aws:iam::${local.env_cfg.account_id}:role/${local.cfg.naming.prefix}-${local.env_cfg.environment}-opensearch-admin")
  access_principal_arns   = ["arn:aws:iam::${local.env_cfg.account_id}:root"]
  tags = {
    team        = "data"
    owner       = local.env_cfg.owner
    pci-scope   = "out-of-scope"
    data-class  = "internal"
    backup-tier = "silver"
  }
}
