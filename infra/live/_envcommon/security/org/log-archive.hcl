locals {
  base = read_terragrunt_config("${get_repo_root()}/infra/live/_envcommon/security/org/baseline.hcl").locals
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
  # Audit ingestion of the central OpenSearch (infra/modules/log-ingestion): reads cloudtrail/ and eks/ only.
  ingest_reader_principal_arns = ["arn:aws:iam::${local.base.cfg.accounts.shared_services}:role/${local.base.prefix}-shared-services-euc1-audit-ingest"]
  ingest_notifications = {
    for src, prefix in { cloudtrail = "cloudtrail/AWSLogs/", eks = "eks/" } : src => {
      prefix                        = prefix
      queue_arn                     = "arn:aws:sqs:${local.base.home_region}:${local.base.cfg.accounts.shared_services}:${local.base.prefix}-shared-services-euc1-audit-${src}"
    }
  }
  tags = local.base.tags
}
