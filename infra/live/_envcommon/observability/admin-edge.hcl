locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}

terraform {
  source = "${get_repo_root()}/infra/modules//admin-edge"
}

# Second step of the apply: set nlb_lookup_enabled to true (and nlb_stack_tag to namespace/name of the internal Gateway) once the Gateway has its NLB
inputs = {
  ca_organization          = "${local.env_cfg.cfg.naming.prefix} platform"
  zone_name                = local.env_cfg.cfg.dns.admin_zone
  permissions_boundary_arn = local.env_cfg.permissions_boundary_arn
  nlb_lookup_enabled       = false
  tags = {
    team        = "platform"
    owner       = local.env_cfg.owner
    pci-scope   = "out-of-scope"
    data-class  = "internal"
    backup-tier = "none"
  }
}
