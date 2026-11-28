locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
  cfg     = local.env_cfg.cfg
  region  = local.cfg.regions.working
}

terraform {
  source = "${get_repo_root()}/infra/modules//opensearch-endpoint"
}

# The central log domain of shared-services (central.opensearch); its owner authorizes this account before the first apply here.
# connected: the endpoint sits in the VPC of the environment, which holds the CDE.
inputs = {
  domain_arn         = "arn:aws:es:${local.region}:${local.cfg.accounts.shared_services}:domain/${local.cfg.central.opensearch.domain_name}"
  client_cidr_blocks = [local.cfg.network[local.env_cfg.environment][local.region]]
  tags = {
    team        = "platform"
    owner       = local.env_cfg.owner
    pci-scope   = "connected"
    data-class  = "internal"
    backup-tier = "none"
  }
}
