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
    cluster_name               = "pay-mock-euc1-eks-edge"
    cluster_arn                = "arn:aws:eks:eu-central-1:000000000000:cluster/pay-mock-euc1-eks-edge"
    cluster_endpoint           = "https://MOCK.gr7.eu-central-1.eks.amazonaws.com"
    certificate_authority_data = "TU9DSw=="
    argocd_cluster_name        = "pay-mock-euc1-edge"
    node_security_group_id     = "sg-00000000"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "kms" {
  config_path = "../../kms"

  mock_outputs = {
    key_arns = {
      "ebs-nodes" = "arn:aws:kms:eu-central-1:000000000000:key/mrk-ebs-nodes"
      "logs"      = "arn:aws:kms:eu-central-1:000000000000:key/mrk-logs"
      "shared"    = "arn:aws:kms:eu-central-1:000000000000:key/mrk-shared"
      "locker"    = "arn:aws:kms:eu-central-1:000000000000:key/mrk-locker"
    }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "dynamodb" {
  config_path = "../../dynamodb"

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
