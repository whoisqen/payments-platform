include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/data/dr-failover.hcl"
  expose = true
}

dependency "kms" {
  config_path = "../kms"

  mock_outputs = {
    key_arns = {
      "shared" = "arn:aws:kms:us-east-1:000000000000:key/mrk-shared"
    }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "routing" {
  config_path = "../../eu-central-1/edge-dns-routing"

  mock_outputs = {
    health_check_ids = {
      "eu-central-1" = "00000000-0000-0000-0000-000000000000"
      "us-east-1"    = "00000000-0000-0000-0000-000000000001"
    }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "dynamodb" {
  config_path = "../../eu-central-1/dynamodb"

  mock_outputs = {
    deny_recovery_writes_policy_arn = "arn:aws:iam::000000000000:policy/mock-deny-recovery-writes"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  kms_key_arn     = dependency.kms.outputs.key_arns["shared"]
  health_check_id = dependency.routing.outputs.health_check_ids[include.envcommon.locals.cfg.regions.working]
  deny_policy_arn = dependency.dynamodb.outputs.deny_recovery_writes_policy_arn
}
