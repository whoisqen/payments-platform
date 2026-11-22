include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/compute/iam-workloads.hcl"
  expose = true
}

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_name           = "pay-mock-euc1-eks"
    cluster_arn            = "arn:aws:eks:eu-central-1:000000000000:cluster/pay-mock-euc1-eks"
    node_security_group_id = "sg-00000000"
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
      "backup"    = "arn:aws:kms:eu-central-1:000000000000:key/mrk-backup"
      "cell-0"    = "arn:aws:kms:eu-central-1:000000000000:key/mrk-cell-0"
      "cell-1"    = "arn:aws:kms:eu-central-1:000000000000:key/mrk-cell-1"
      "cell-2"    = "arn:aws:kms:eu-central-1:000000000000:key/mrk-cell-2"
      "cell-3"    = "arn:aws:kms:eu-central-1:000000000000:key/mrk-cell-3"
      "spare"     = "arn:aws:kms:eu-central-1:000000000000:key/mrk-spare"
    }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "memorydb" {
  config_path = "../memorydb"

  mock_outputs = {
    cluster_arn = "arn:aws:memorydb:eu-central-1:000000000000:cluster/mock"
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

dependency "secrets" {
  config_path = "../../secrets"

  mock_outputs = {
    secret_arns = {
      router = "arn:aws:secretsmanager:eu-central-1:000000000000:secret:mock-AbCdEf"
    }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  cell                            = "cell-2"
  cluster_name                    = dependency.eks.outputs.cluster_name
  cluster_arn                     = dependency.eks.outputs.cluster_arn
  deny_recovery_writes_policy_arn = dependency.dynamodb.outputs.deny_recovery_writes_policy_arn
  dynamodb_table_arn              = dependency.dynamodb.outputs.table_arn
  locker_kms_key_arn              = dependency.kms.outputs.key_arns["locker"]
  secrets_kms_key_arn             = dependency.kms.outputs.key_arns["shared"]
  secret_arns                     = values(dependency.secrets.outputs.secret_arns)
  memorydb = {
    cluster_arn = dependency.memorydb.outputs.cluster_arn
    users       = { for u, _ in include.envcommon.locals.env_cfg.memorydb_users : u => u }
  }
  # The aurora-global module does not export the proxy resource id yet, so rds-db:connect ARNs stay empty.
  rds_db_connect_arns = {}
}
