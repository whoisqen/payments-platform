locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}

# Pilot light (D6, D7): built by the region switch within the RTO, not kept running; excluding a unit does not destroy it.
exclude {
  if                   = !try(local.env_cfg.standby_compute_enabled, get_env("PAY_STANDBY_COMPUTE", "false") == "true")
  actions              = ["all"]
  exclude_dependencies = false
}

include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/shared-clusters/iam-workloads.hcl"
  expose = true
}

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_name               = "pay-mock-use1-eks-control-center"
    cluster_arn                = "arn:aws:eks:us-east-1:000000000000:cluster/pay-mock-use1-eks-control-center"
    cluster_endpoint           = "https://MOCK.gr7.us-east-1.eks.amazonaws.com"
    certificate_authority_data = "TU9DSw=="
    argocd_cluster_name        = "pay-mock-use1-control-center"
    node_security_group_id     = "sg-00000000"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "kms" {
  config_path = "../../kms"

  mock_outputs = {
    key_arns = {
      "ebs-nodes" = "arn:aws:kms:us-east-1:000000000000:key/mrk-ebs-nodes"
      "logs"      = "arn:aws:kms:us-east-1:000000000000:key/mrk-logs"
      "shared"    = "arn:aws:kms:us-east-1:000000000000:key/mrk-shared"
      "locker"    = "arn:aws:kms:us-east-1:000000000000:key/mrk-locker"
    }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "dynamodb" {
  config_path = "../../../eu-central-1/dynamodb"

  mock_outputs = {
    table_arn                       = "arn:aws:dynamodb:eu-central-1:000000000000:table/mock"
    deny_recovery_writes_policy_arn = "arn:aws:iam::000000000000:policy/mock"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

# External Secrets of this cluster reads Vault, not Secrets Manager, so secret_arns stays empty.
inputs = {
  cluster_name                    = dependency.eks.outputs.cluster_name
  cluster_arn                     = dependency.eks.outputs.cluster_arn
  deny_recovery_writes_policy_arn = dependency.dynamodb.outputs.deny_recovery_writes_policy_arn
  secrets_kms_key_arn             = dependency.kms.outputs.key_arns["shared"]
}
