locals {
  base = read_terragrunt_config("${get_repo_root()}/infra/live/_envcommon/security/baseline.hcl").locals

  # security-baseline stays off the Security OU: it denies guardduty:UpdateDetector and conformance pack deletes that the audit stacks need.
  default_targets = {
    "security-baseline"                     = ["infrastructure", "workloads_cde", "workloads_noncde", "sandbox"]
    "region-allow-list"                     = ["root"]
    "deny-tag-edit"                         = ["infrastructure", "workloads_cde", "workloads_noncde"]
    "deny-dynamodb-writes-recovery-regions" = ["workloads_cde", "workloads_noncde"]
    "required-tags"                         = ["infrastructure", "workloads_cde", "workloads_noncde"]
    "backup-tiers"                          = ["infrastructure", "workloads_cde", "workloads_noncde"]
  }
}

terraform {
  source = "${get_repo_root()}/infra/modules//org-policies"
}

inputs = {
  policy_dir      = "${get_repo_root()}/policy/scp"
  organization_id = local.base.organization_id
  target_ids      = local.base.target_ids
  policy_targets  = try(local.base.org.policy_targets, local.default_targets)
  rcp_targets     = try(local.base.org.rcp_targets, ["workloads_cde"])
  tags            = local.base.tags
}
