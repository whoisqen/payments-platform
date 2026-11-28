# Cross-cluster entry of a cell from the edge: internal NLB -> mutual-TLS router gateway of the cell (deploy/charts/payments-cell).
locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
  cell    = basename(dirname(get_terragrunt_dir()))
}

terraform {
  source = "${get_repo_root()}/infra/modules//cell-endpoint"
}

inputs = {
  cell                     = local.cell
  cluster_domain           = local.env_cfg.cfg.deploy[local.env_cfg.environment].cluster_domain
  permissions_boundary_arn = local.env_cfg.permissions_boundary_arn
  tags = {
    team        = "payments-core"
    owner       = local.env_cfg.owner
    pci-scope   = "cde"
    data-class  = "card-data"
    backup-tier = "none"
  }
}
