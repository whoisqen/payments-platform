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
    cluster_name               = "pay-mock-euc1-eks-spare"
    cluster_arn                = "arn:aws:eks:eu-central-1:000000000000:cluster/pay-mock-euc1-eks-spare"
    cluster_endpoint           = "https://MOCK.gr7.eu-central-1.eks.amazonaws.com"
    certificate_authority_data = "TU9DSw=="
    oidc_issuer                = "https://oidc.eks.eu-central-1.amazonaws.com/id/MOCK"
    argocd_cluster_name        = "pay-mock-euc1-spare"
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
