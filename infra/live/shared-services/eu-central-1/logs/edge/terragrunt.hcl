include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
  # Host of central.logs_otlp_endpoint without scheme and port
  host = regex("^https?://([^:/]+)", local.env_cfg.cfg.central.logs_otlp_endpoint)[0]
}

terraform {
  source = "${get_repo_root()}/infra/modules//logs-edge"
}

dependency "vpc" {
  config_path = "../../vpc"

  mock_outputs = {
    vpc_id = "vpc-00000000"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "kms" {
  config_path = "../../kms"

  mock_outputs = {
    key_arns = {
      "shared" = "arn:aws:kms:eu-central-1:000000000000:key/mrk-shared"
    }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "admin_edge" {
  config_path = "../../admin-edge"

  mock_outputs = {
    ca_arn = "arn:aws:acm-pca:eu-central-1:000000000000:certificate-authority/00000000-0000-0000-0000-000000000000"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

# Second step: set nlb_lookup_enabled = true once the logs Gateway (deploy/platform/logstash) has its NLB.
inputs = {
  host                      = local.host
  certificate_authority_arn = dependency.admin_edge.outputs.ca_arn
  kms_key_arn               = dependency.kms.outputs.key_arns["shared"]
  vpc_ids                   = [dependency.vpc.outputs.vpc_id]
  nlb_lookup_enabled        = false
  nlb_stack_tag             = "monitoring/logs"
  tags = {
    team        = "platform"
    owner       = local.env_cfg.owner
    pci-scope   = "out-of-scope"
    data-class  = "internal"
    backup-tier = "none"
  }
}
