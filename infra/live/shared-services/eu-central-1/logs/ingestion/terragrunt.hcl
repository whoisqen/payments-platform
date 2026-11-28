include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/observability/logs-ingestion.hcl"
  expose = true
}

dependency "vpc" {
  config_path = "../../vpc"

  mock_outputs = {
    vpc_id = "vpc-00000000"
    subnet_ids = {
      public  = ["subnet-a00000000", "subnet-a10000000", "subnet-a20000000"]
      private = ["subnet-b00000000", "subnet-b10000000", "subnet-b20000000"]
      data    = ["subnet-c00000000", "subnet-c10000000", "subnet-c20000000"]
    }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "kms" {
  config_path = "../../kms"

  mock_outputs = {
    key_arns = {
      "logs"   = "arn:aws:kms:eu-central-1:000000000000:key/mrk-logs"
      "shared" = "arn:aws:kms:eu-central-1:000000000000:key/mrk-shared"
    }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "eks" {
  config_path = "../../central/eks"

  mock_outputs = {
    cluster_name      = "pay-shared-services-euc1-central"
    oidc_provider_arn = "arn:aws:iam::000000000000:oidc-provider/oidc.eks.eu-central-1.amazonaws.com/id/MOCK"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "domain" {
  config_path = "../opensearch"

  mock_outputs = {
    domain_arn               = "arn:aws:es:eu-central-1:000000000000:domain/pay-mock-logs"
    endpoint                 = "vpc-pay-mock-logs-000000.eu-central-1.es.amazonaws.com"
    client_security_group_id = "sg-00000001"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  domain_arn               = dependency.domain.outputs.domain_arn
  domain_endpoint          = dependency.domain.outputs.endpoint
  client_security_group_id = dependency.domain.outputs.client_security_group_id
  oidc_provider_arn        = dependency.eks.outputs.oidc_provider_arn
  cluster_name             = dependency.eks.outputs.cluster_name
  subnet_ids               = dependency.vpc.outputs.subnet_ids["private"]
  kms_key_arn              = dependency.kms.outputs.key_arns["shared"]
  logs_kms_key_arn         = dependency.kms.outputs.key_arns["logs"]
}
