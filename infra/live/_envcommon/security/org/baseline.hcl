# Ids and names the security baseline stacks share; organization.* and accounts.* keys fall back to placeholders until the owner sets them.
locals {
  cfg    = yamldecode(file("${get_repo_root()}/config/platform.yaml"))
  org    = try(local.cfg.organization, {})
  sec    = try(local.cfg.security, {})
  prefix = local.cfg.naming.prefix

  home_region = local.cfg.regions.working
  regions     = concat([local.home_region], local.cfg.regions.recovery)

  organization_id = try(local.org.id, "o-0000000000")
  target_ids = {
    root             = try(local.org.root_id, "r-0000")
    security         = try(local.org.ou_ids.security, "ou-0000-00000001")
    infrastructure   = try(local.org.ou_ids.infrastructure, "ou-0000-00000002")
    workloads_cde    = try(local.org.ou_ids.workloads_cde, "ou-0000-00000003")
    workloads_noncde = try(local.org.ou_ids.workloads_noncde, "ou-0000-00000004")
    sandbox          = try(local.org.ou_ids.sandbox, "ou-0000-00000005")
  }

  management_account_id  = try(local.cfg.accounts.management, "000000000001")
  log_archive_account_id = try(local.cfg.accounts.log_archive, "000000000002")
  audit_account_id       = try(local.cfg.accounts.audit, "000000000003")
  member_account_ids = try(local.sec.member_account_ids, distinct([
    for k, id in local.cfg.accounts : id if !contains(["management", "audit"], k)
  ]))
  cde_account_ids        = try(local.sec.cde_account_ids, try(local.cfg.ai.cde_account_ids, []))
  cde_s3_bucket_prefixes = try(local.sec.cde_s3_bucket_prefixes, ["${local.prefix}-cde-"])

  # Fixed names break the cycle between the trail (needs the bucket) and the bucket policy (needs the trail ARN).
  trail_name      = "${local.prefix}-management-euc1-org-trail"
  trail_arn       = "arn:aws:cloudtrail:${local.home_region}:${local.management_account_id}:trail/${local.trail_name}"
  log_bucket_name = "${local.prefix}-security-euc1-log-archive"

  tags = {
    team        = "security"
    owner       = try(local.sec.owner_email, local.cfg.owner.contact_email)
    pci-scope   = "connected"
    data-class  = "internal"
    backup-tier = "none"
  }
}
