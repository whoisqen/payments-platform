include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/analytics/msk.hcl"
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

dependency "access" {
  config_path = "../msk-access"

  mock_outputs = {
    security_group_ids = { msk = "sg-00000001" }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "event_archive" {
  config_path = "../../s3-event-archive"

  mock_outputs = {
    bucket_arns = { "eu-central-1" = "arn:aws:s3:::pay-prod-euc1-event-archive" }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

# The kafka-topics Job and the kafka-exporter run on the analytics cluster and get their MSK roles through Pod Identity there
dependency "analytics_eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_name = "pay-prod-euc1-eks-analytics"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

# The archive bucket policy keeps its own statements: the sink role writes there by its IAM policy in the same account.
inputs = {
  kms_key_arn         = dependency.kms.outputs.key_arns["shared"]
  logs_kms_key_arn    = dependency.kms.outputs.key_arns["logs"]
  client_subnets      = dependency.vpc.outputs.subnet_ids["data"]
  security_group_ids  = [dependency.access.outputs.security_group_ids["msk"]]
  sink_bucket_arn     = dependency.event_archive.outputs.bucket_arns["eu-central-1"]
  sink_kms_key_arn    = dependency.kms.outputs.key_arns["shared"]
  client_cluster_name = dependency.analytics_eks.outputs.cluster_name
}
