include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/data/cell-migration.hcl"
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
      "cell-0"    = "arn:aws:kms:eu-central-1:000000000000:key/mrk-cell-0"
      "cell-1"    = "arn:aws:kms:eu-central-1:000000000000:key/mrk-cell-1"
      "cell-2"    = "arn:aws:kms:eu-central-1:000000000000:key/mrk-cell-2"
      "cell-3"    = "arn:aws:kms:eu-central-1:000000000000:key/mrk-cell-3"
      "spare"     = "arn:aws:kms:eu-central-1:000000000000:key/mrk-spare"
    }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "aurora_cell_0" {
  config_path = "../cell-0/aurora"

  mock_outputs = {
    proxy_endpoint         = "mock-cell-0.proxy-mock.eu-central-1.rds.amazonaws.com"
    proxy_auth_secret_arns = { hs_app = "arn:aws:secretsmanager:eu-central-1:000000000000:secret:mock-cell-0-AbCdEf" }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "access_cell_0" {
  config_path = "../cell-0/data-access"

  mock_outputs = {
    security_group_ids = { aurora-proxy = "sg-00000000" }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "aurora_cell_1" {
  config_path = "../cell-1/aurora"

  mock_outputs = {
    proxy_endpoint         = "mock-cell-1.proxy-mock.eu-central-1.rds.amazonaws.com"
    proxy_auth_secret_arns = { hs_app = "arn:aws:secretsmanager:eu-central-1:000000000000:secret:mock-cell-1-AbCdEf" }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "access_cell_1" {
  config_path = "../cell-1/data-access"

  mock_outputs = {
    security_group_ids = { aurora-proxy = "sg-00000000" }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "aurora_cell_2" {
  config_path = "../cell-2/aurora"

  mock_outputs = {
    proxy_endpoint         = "mock-cell-2.proxy-mock.eu-central-1.rds.amazonaws.com"
    proxy_auth_secret_arns = { hs_app = "arn:aws:secretsmanager:eu-central-1:000000000000:secret:mock-cell-2-AbCdEf" }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "access_cell_2" {
  config_path = "../cell-2/data-access"

  mock_outputs = {
    security_group_ids = { aurora-proxy = "sg-00000000" }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "aurora_cell_3" {
  config_path = "../cell-3/aurora"

  mock_outputs = {
    proxy_endpoint         = "mock-cell-3.proxy-mock.eu-central-1.rds.amazonaws.com"
    proxy_auth_secret_arns = { hs_app = "arn:aws:secretsmanager:eu-central-1:000000000000:secret:mock-cell-3-AbCdEf" }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "access_cell_3" {
  config_path = "../cell-3/data-access"

  mock_outputs = {
    security_group_ids = { aurora-proxy = "sg-00000000" }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "aurora_spare" {
  config_path = "../spare/aurora"

  mock_outputs = {
    proxy_endpoint         = "mock-spare.proxy-mock.eu-central-1.rds.amazonaws.com"
    proxy_auth_secret_arns = { hs_app = "arn:aws:secretsmanager:eu-central-1:000000000000:secret:mock-spare-AbCdEf" }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "access_spare" {
  config_path = "../spare/data-access"

  mock_outputs = {
    security_group_ids = { aurora-proxy = "sg-00000000" }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  vpc_id               = dependency.vpc.outputs.vpc_id
  subnet_ids           = dependency.vpc.outputs.subnet_ids["private"]
  secrets_kms_key_arns = [for c in ["cell-0", "cell-1", "cell-2", "cell-3", "spare"] : dependency.kms.outputs.key_arns[c]]
  cells = {
    "cell-0" = {
      proxy_endpoint          = dependency.aurora_cell_0.outputs.proxy_endpoint
      proxy_security_group_id = dependency.access_cell_0.outputs.security_group_ids["aurora-proxy"]
      login_secret_arn        = dependency.aurora_cell_0.outputs.proxy_auth_secret_arns["hs_app"]
    }
    "cell-1" = {
      proxy_endpoint          = dependency.aurora_cell_1.outputs.proxy_endpoint
      proxy_security_group_id = dependency.access_cell_1.outputs.security_group_ids["aurora-proxy"]
      login_secret_arn        = dependency.aurora_cell_1.outputs.proxy_auth_secret_arns["hs_app"]
    }
    "cell-2" = {
      proxy_endpoint          = dependency.aurora_cell_2.outputs.proxy_endpoint
      proxy_security_group_id = dependency.access_cell_2.outputs.security_group_ids["aurora-proxy"]
      login_secret_arn        = dependency.aurora_cell_2.outputs.proxy_auth_secret_arns["hs_app"]
    }
    "cell-3" = {
      proxy_endpoint          = dependency.aurora_cell_3.outputs.proxy_endpoint
      proxy_security_group_id = dependency.access_cell_3.outputs.security_group_ids["aurora-proxy"]
      login_secret_arn        = dependency.aurora_cell_3.outputs.proxy_auth_secret_arns["hs_app"]
    }
    "spare" = {
      proxy_endpoint          = dependency.aurora_spare.outputs.proxy_endpoint
      proxy_security_group_id = dependency.access_spare.outputs.security_group_ids["aurora-proxy"]
      login_secret_arn        = dependency.aurora_spare.outputs.proxy_auth_secret_arns["hs_app"]
    }
  }
}
