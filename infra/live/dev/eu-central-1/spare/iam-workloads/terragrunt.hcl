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

dependency "msk" {
  config_path = "../../analytics/msk"

  mock_outputs = {
    producer_policy_arn = "arn:aws:iam::000000000000:policy/pay-mock-euc1-msk-producer"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "aurora" {
  config_path = "../aurora"

  mock_outputs = {
    cluster_resource_id = "cluster-MOCK"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "backup" {
  config_path = "../../backup"

  mock_outputs = {
    vault_arns      = { "eu-central-1" = "arn:aws:backup:eu-central-1:000000000000:backup-vault:mock" }
    backup_role_arn = "arn:aws:iam::000000000000:role/mock-backup"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  cell             = "spare"
  cell_kms_key_arn = dependency.kms.outputs.key_arns["spare"]
  # The migration Job logs in to the writer as hs_migrator with an IAM token and snapshots the cell first (D3).
  migrator = {
    db_connect_arns  = ["arn:aws:rds-db:${include.root.locals.region}:${include.root.locals.env_cfg.account_id}:dbuser:${dependency.aurora.outputs.cluster_resource_id}/hs_migrator"]
    backup_vault_arn = dependency.backup.outputs.vault_arns[include.root.locals.region]
    backup_role_arn  = dependency.backup.outputs.backup_role_arn
  }
  cluster_name                    = dependency.eks.outputs.cluster_name
  cluster_arn                     = dependency.eks.outputs.cluster_arn
  deny_recovery_writes_policy_arn = dependency.dynamodb.outputs.deny_recovery_writes_policy_arn
  dynamodb_table_arn              = dependency.dynamodb.outputs.table_arn
  locker_kms_key_arn              = dependency.kms.outputs.key_arns["locker"]
  secrets_kms_key_arn             = dependency.kms.outputs.key_arns["shared"]
  secret_arns                     = values(dependency.secrets.outputs.secret_arns)
  kafka_producer_policy_arn       = dependency.msk.outputs.producer_policy_arn
  memorydb = {
    cluster_arn = dependency.memorydb.outputs.cluster_arn
    users       = { for u, _ in include.envcommon.locals.env_cfg.memorydb_users : u => u }
  }
  # The aurora-global module does not export the proxy resource id yet, so rds-db:connect ARNs stay empty.
  rds_db_connect_arns = {}
}
