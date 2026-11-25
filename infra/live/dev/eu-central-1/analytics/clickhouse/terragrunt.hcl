include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/analytics/clickhouse.hcl"
  expose = true
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
  config_path = "../eks"

  mock_outputs = {
    cluster_name           = "pay-mock-euc1-eks-analytics"
    cluster_arn            = "arn:aws:eks:eu-central-1:000000000000:cluster/pay-mock-euc1-eks-analytics"
    node_security_group_id = "sg-00000000"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "backup" {
  config_path = "../../s3-backup"

  mock_outputs = {
    bucket_arns = { "eu-central-1" = "arn:aws:s3:::pay-dev-euc1-backup" }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "event_archive" {
  config_path = "../../s3-event-archive"

  mock_outputs = {
    bucket_arns = { "eu-central-1" = "arn:aws:s3:::pay-dev-euc1-event-archive" }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

# ClickHouse runs in the analytics cluster; backups go to the backup bucket, restores replay the event archive.
inputs = {
  cluster_name        = dependency.eks.outputs.cluster_name
  kms_key_arn         = dependency.kms.outputs.key_arns["shared"]
  backup_bucket_arn   = dependency.backup.outputs.bucket_arns["eu-central-1"]
  archive_bucket_arn  = dependency.event_archive.outputs.bucket_arns["eu-central-1"]
  archive_kms_key_arn = dependency.kms.outputs.key_arns["shared"]
}
