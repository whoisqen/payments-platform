locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
  region  = basename(dirname(get_terragrunt_dir()))
}

terraform {
  source = "${get_repo_root()}/infra/modules//egress-routing"
}

# Workload VPC of this environment and region; the transit gateway carries its traffic to the egress VPC and back.
inputs = {
  azs            = local.env_cfg.azs[local.region]
  workload_cidrs = [local.env_cfg.vpc_cidrs[local.region]]
}
