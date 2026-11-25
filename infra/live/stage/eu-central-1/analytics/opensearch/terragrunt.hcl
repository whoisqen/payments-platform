include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/analytics/opensearch.hcl"
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
  config_path = "../opensearch-access"

  mock_outputs = {
    security_group_ids = { opensearch = "sg-00000001" }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "backup" {
  config_path = "../../s3-backup"

  mock_outputs = {
    bucket_arns = { "eu-central-1" = "arn:aws:s3:::pay-stage-euc1-backup" }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  kms_key_arn          = dependency.kms.outputs.key_arns["shared"]
  logs_kms_key_arn     = dependency.kms.outputs.key_arns["logs"]
  subnet_ids           = dependency.vpc.outputs.subnet_ids["data"]
  security_group_ids   = [dependency.access.outputs.security_group_ids["opensearch"]]
  snapshot_bucket_arn  = dependency.backup.outputs.bucket_arns["eu-central-1"]
  snapshot_kms_key_arn = dependency.kms.outputs.key_arns["shared"]
}
