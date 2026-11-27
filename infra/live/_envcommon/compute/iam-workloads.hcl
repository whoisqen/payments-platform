locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}

terraform {
  source = "${get_repo_root()}/infra/modules//iam-workloads"
}

# Cells run router, drainer, scheduler and the migration Job (deploy/charts/payments-cell); the locker has its own cluster.
inputs = {
  services                 = ["router", "drainer", "scheduler"]
  permissions_boundary_arn = local.env_cfg.permissions_boundary_arn
  tags = {
    team        = "payments-core"
    owner       = local.env_cfg.owner
    pci-scope   = "cde"
    data-class  = "internal"
    backup-tier = "none"
  }
}
