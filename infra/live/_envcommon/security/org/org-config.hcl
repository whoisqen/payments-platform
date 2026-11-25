locals {
  base    = read_terragrunt_config("${get_repo_root()}/infra/live/_envcommon/security/org/baseline.hcl").locals
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}

terraform {
  source = "${get_repo_root()}/infra/modules//org-config"
}

# The same component runs in the management account (delegation) and in the audit account (aggregator, recorders, pack).
inputs = {
  mode                       = local.env_cfg.environment == "management" ? "management" : "admin"
  regions                    = local.base.regions
  admin_account_id           = local.base.audit_account_id
  recorder_stack_set_enabled = try(local.base.sec.config_recorder_stack_set_enabled, true)
  create_service_linked_role = try(local.base.sec.config_create_service_linked_role, true)
  recorder_target_ou_ids     = [for k in ["security", "infrastructure", "workloads_cde", "workloads_noncde", "sandbox"] : local.base.target_ids[k]]
  conformance_pack_template  = file("${get_repo_root()}/policy/config/pci-dss-pack/pci-dss-v4.yaml")
  tags                       = local.base.tags
}
