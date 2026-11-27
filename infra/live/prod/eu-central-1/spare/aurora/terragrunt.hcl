include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/data/aurora.hcl"
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
  component                = "aurora-spare"
  kms_key_arn              = dependency.kms.outputs.key_arns["spare"]
  db_subnet_group_name     = dependency.data_access.outputs.db_subnet_group_name
  security_group_ids       = [dependency.data_access.outputs.security_group_ids["aurora"]]
  proxy_security_group_ids = [dependency.data_access.outputs.security_group_ids["aurora-proxy"]]
  proxy_subnet_ids         = dependency.vpc.outputs.subnet_ids["data"]
  availability_zones       = include.envcommon.locals.env_cfg.azs["eu-central-1"]
  # Writers rotate over the AZs so that one AZ loss never takes every writer.
  writer_az = include.envcommon.locals.env_cfg.azs["eu-central-1"][1]

  # Minimal profile of the spare (section 12); the merchant-move runbook raises it to the cell classes before a hot merchant lands.
  writer_instance_class = "db.r7g.2xlarge"
  reader_instance_class = "db.r7g.2xlarge"
  # Low I/O while empty: Standard storage is cheaper than I/O-Optimized here.
  storage_type = "aurora"
}
