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
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/compute/argocd-registration.hcl"
  expose = true
}

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_name               = "pay-mock-use1-eks-control-center"
    cluster_arn                = "arn:aws:eks:us-east-1:000000000000:cluster/pay-mock-use1-eks-control-center"
    cluster_endpoint           = "https://MOCK.gr7.us-east-1.eks.amazonaws.com"
    certificate_authority_data = "TU9DSw=="
    oidc_issuer                = "https://oidc.eks.eu-central-1.amazonaws.com/id/MOCK"
    argocd_cluster_name        = "pay-mock-use1-control-center"
    node_security_group_id     = "sg-00000000"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  argocd_cluster_name        = dependency.eks.outputs.argocd_cluster_name
  cluster_name               = dependency.eks.outputs.cluster_name
  cluster_endpoint           = dependency.eks.outputs.cluster_endpoint
  certificate_authority_data = dependency.eks.outputs.certificate_authority_data
  oidc_issuer                = dependency.eks.outputs.oidc_issuer
}
