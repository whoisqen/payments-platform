locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}

terraform {
  source = "${get_repo_root()}/infra/modules//tf-exec-role"
}

# The first apply runs with direct credentials (PAY_TF_DIRECT=true): the role the generated provider assumes is created here.
# No boundary: modules create service roles (RDS Proxy, AWS Backup, S3 replication) that carry none, and the boundary itself is applied through this role.
inputs = {
  shared_services_account_id = local.env_cfg.shared_services_account_id
  tags = {
    team        = "platform"
    owner       = local.env_cfg.owner
    pci-scope   = "connected"
    data-class  = "internal"
    backup-tier = "none"
  }
}
