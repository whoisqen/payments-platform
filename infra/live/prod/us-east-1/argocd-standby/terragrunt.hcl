locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}

# Follows the standby cells: excluded only when their fallback switch excludes them too.
exclude {
  if                   = !local.env_cfg.standby_compute_enabled
  actions              = ["all"]
  exclude_dependencies = false
}

include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/compute/argocd-standby.hcl"
  expose = true
}

dependency "eks_cell_0" {
  config_path = "../cell-0/eks"

  mock_outputs = {
    cluster_name      = "pay-mock-use1-eks-cell-0"
    oidc_provider_arn = "arn:aws:iam::000000000000:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/MOCK"
    oidc_issuer       = "oidc.eks.us-east-1.amazonaws.com/id/MOCK"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "eks_cell_1" {
  config_path = "../cell-1/eks"

  mock_outputs = {
    cluster_name      = "pay-mock-use1-eks-cell-1"
    oidc_provider_arn = "arn:aws:iam::000000000000:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/MOCK"
    oidc_issuer       = "oidc.eks.us-east-1.amazonaws.com/id/MOCK"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "eks_cell_2" {
  config_path = "../cell-2/eks"

  mock_outputs = {
    cluster_name      = "pay-mock-use1-eks-cell-2"
    oidc_provider_arn = "arn:aws:iam::000000000000:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/MOCK"
    oidc_issuer       = "oidc.eks.us-east-1.amazonaws.com/id/MOCK"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "eks_cell_3" {
  config_path = "../cell-3/eks"

  mock_outputs = {
    cluster_name      = "pay-mock-use1-eks-cell-3"
    oidc_provider_arn = "arn:aws:iam::000000000000:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/MOCK"
    oidc_issuer       = "oidc.eks.us-east-1.amazonaws.com/id/MOCK"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "eks_spare" {
  config_path = "../spare/eks"

  mock_outputs = {
    cluster_name      = "pay-mock-use1-eks-spare"
    oidc_provider_arn = "arn:aws:iam::000000000000:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/MOCK"
    oidc_issuer       = "oidc.eks.us-east-1.amazonaws.com/id/MOCK"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

# Argo CD core runs in cell-0, the first standby cell; the eks outputs come from the bucket that PAY_STATE_REGION selects.
inputs = {
  host_cluster = {
    name              = dependency.eks_cell_0.outputs.cluster_name
    oidc_provider_arn = dependency.eks_cell_0.outputs.oidc_provider_arn
    oidc_issuer       = dependency.eks_cell_0.outputs.oidc_issuer
  }
  clusters = {
    cell-0 = dependency.eks_cell_0.outputs.cluster_name
    cell-1 = dependency.eks_cell_1.outputs.cluster_name
    cell-2 = dependency.eks_cell_2.outputs.cluster_name
    cell-3 = dependency.eks_cell_3.outputs.cluster_name
    spare  = dependency.eks_spare.outputs.cluster_name
  }
}
