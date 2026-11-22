include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/compute/ci-runners.hcl"
  expose = true
}

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    oidc_provider_arn = "arn:aws:iam::000000000000:oidc-provider/oidc.eks.eu-central-1.amazonaws.com/id/MOCK"
    oidc_issuer       = "oidc.eks.eu-central-1.amazonaws.com/id/MOCK"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate"]
}

inputs = {
  oidc_provider_arn = dependency.eks.outputs.oidc_provider_arn
  oidc_issuer       = dependency.eks.outputs.oidc_issuer
  tags = {
    team        = "platform"
    owner       = include.envcommon.locals.env_cfg.owner
    pci-scope   = "out-of-scope"
    data-class  = "internal"
    backup-tier = "none"
  }
}
