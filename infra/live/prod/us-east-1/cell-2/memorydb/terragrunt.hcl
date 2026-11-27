locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}

# Hot standby: applied all the time; the exclude is only a fallback switch and excluding a unit does not destroy it.
exclude {
  if                   = !local.env_cfg.standby_compute_enabled
  actions              = ["all"]
  exclude_dependencies = false
}

include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/data/memorydb.hcl"
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

dependency "data_access" {
  config_path = "../data-access"

  mock_outputs = {
    security_group_ids = {
      aurora       = "sg-00000001"
      aurora-proxy = "sg-00000002"
      memorydb     = "sg-00000003"
    }
    db_subnet_group_name = "mock"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  component          = "memorydb-cell-2"
  kms_key_arn        = dependency.kms.outputs.key_arns["cell-2"]
  subnet_ids         = dependency.vpc.outputs.subnet_ids["data"]
  security_group_ids = [dependency.data_access.outputs.security_group_ids["memorydb"]]
}
