locals {
  base = read_terragrunt_config("${get_repo_root()}/infra/live/_envcommon/security/baseline.hcl").locals
}

terraform {
  source = "${get_repo_root()}/infra/modules//org-trail"
}

inputs = {
  component              = "org-trail"
  cde_s3_bucket_prefixes = local.base.cde_s3_bucket_prefixes
  log_retention_days     = try(local.base.sec.trail_log_retention_days, 90)
  tags                   = local.base.tags
}
