locals {
  base = read_terragrunt_config("${get_repo_root()}/infra/live/_envcommon/security/baseline.hcl").locals
}

terraform {
  source = "${get_repo_root()}/infra/modules//log-archive"
}

inputs = {
  component             = "log-archive"
  organization_id       = local.base.organization_id
  management_account_id = local.base.management_account_id
  trail_arn             = local.base.trail_arn
  reader_principal_arns = try(local.base.sec.log_reader_principal_arns, [])
  tags                  = local.base.tags
}
