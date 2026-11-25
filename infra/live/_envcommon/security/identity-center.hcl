locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
  access  = local.env_cfg.cfg.access
  ic      = try(local.access.identity_center, {})

  # One small file per grant list keeps the JIT PR reviewable; a missing file means no grant.
  grants_file = "${get_repo_root()}/config/access/cde-jit-grants.yaml"
  grants      = fileexists(local.grants_file) ? try(yamldecode(file(local.grants_file)).grants, []) : []
}

terraform {
  source = "${get_repo_root()}/infra/modules//identity-center"
}

# Instance and store ids are placeholders until the owner fills access.identity_center; a plan then fails at the identity store lookups.
inputs = {
  instance_arn            = try(local.ic.instance_arn, "arn:aws:sso:::instance/ssoins-0000000000000000")
  identity_store_id       = try(local.ic.identity_store_id, "d-0000000000")
  accounts                = merge({ for k, v in local.env_cfg.cfg.accounts : replace(k, "_", "-") => v }, { management = local.env_cfg.account_id })
  management_account      = "management"
  cde_accounts            = try(local.ic.cde_accounts, ["prod"])
  sre_view_permission_set = trimprefix(local.access.sre_view_permission_set, "AWSReservedSSO_")
  sre_view_groups         = try(local.ic.sre_view_groups, [local.access.grafana_groups.sre])
  assignments             = try(local.ic.assignments, {})
  cde_jit_grants          = local.grants
  # The scheduled revocation job sets CDE_JIT_REVOCATION_RUN=true so expired grants are destroyed instead of failing the plan.
  revocation_run = get_env("CDE_JIT_REVOCATION_RUN", "false") == "true"
  tags = {
    team        = "security"
    owner       = local.env_cfg.owner
    pci-scope   = "connected"
    data-class  = "internal"
    backup-tier = "none"
  }
}
