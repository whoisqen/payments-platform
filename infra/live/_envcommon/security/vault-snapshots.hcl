locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}

terraform {
  source = "${get_repo_root()}/infra/modules//s3-backup"
}

inputs = {
  component = "vault-snapshots"
  # Raft snapshots only; the module default prefixes belong to the other buckets.
  lifecycle_prefixes = ["raft/"]
  tags = {
    team        = "security"
    owner       = local.env_cfg.owner
    pci-scope   = "cde"
    data-class  = "internal"
    backup-tier = "silver"
  }
}
