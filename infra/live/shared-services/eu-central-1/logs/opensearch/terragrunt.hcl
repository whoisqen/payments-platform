include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/observability/logs-domain.hcl"
  expose = true
}

dependency "vpc" {
  config_path = "../../vpc"

  mock_outputs = {
    vpc_id         = "vpc-00000000"
    vpc_cidr_block = "10.0.0.0/16"
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
      "ebs-nodes" = "arn:aws:kms:eu-central-1:000000000000:key/mrk-ebs-nodes"
      "logs"      = "arn:aws:kms:eu-central-1:000000000000:key/mrk-logs"
      "shared"    = "arn:aws:kms:eu-central-1:000000000000:key/mrk-shared"
    }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "eks" {
  config_path = "../../central/eks"

  mock_outputs = {
    cluster_name           = "pay-shared-services-euc1-central"
    node_security_group_id = "sg-00000000"
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

# Logstash and the Dashboards proxy of the admin gateway run on the central cluster nodes.
inputs = {
  vpc_id                    = dependency.vpc.outputs.vpc_id
  subnet_ids                = dependency.vpc.outputs.subnet_ids["data"]
  client_security_group_ids = [dependency.eks.outputs.node_security_group_id]
  kms_key_arn               = dependency.kms.outputs.key_arns["shared"]
  logs_kms_key_arn          = dependency.kms.outputs.key_arns["logs"]
  # Dashboards on the admin host (the wildcard of the admin zone reaches the internal gateway), certificate from the private CA
  custom_endpoint = {
    host                      = include.envcommon.locals.cfg.central.opensearch.dashboards_host
    certificate_authority_arn = dependency.admin_edge.outputs.ca_arn
  }
}
