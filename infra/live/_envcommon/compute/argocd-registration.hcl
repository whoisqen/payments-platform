# Argo CD registration of the eks unit next to it: the secret lives in shared-services, so this unit replaces the root provider.
locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
  cfg     = local.env_cfg.cfg
  prefix  = local.cfg.naming.prefix
  path    = regex("/live/(?P<env>[^/]+)/(?P<region>[^/]+)/(?P<cluster>[^/]+)/", get_terragrunt_dir())
  ss      = local.cfg.accounts.shared_services
  working = local.cfg.regions.working
  short   = { "eu-central-1" = "euc1", "us-east-1" = "use1" }
}

terraform {
  source = "${get_repo_root()}/infra/modules//argocd-registration"
}

generate "provider_registration" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOT
    provider "aws" {
      region              = "${local.working}"
      allowed_account_ids = ["${local.ss}"]

      assume_role {
        role_arn     = "arn:aws:iam::${local.ss}:role/${local.prefix}-shared-services-argocd-registration"
        session_name = "argocd-registration-${local.path.env}"
      }

      default_tags {
        tags = {
          environment = "${local.path.env}"
          cell        = "${local.path.cluster}"
          component   = "argocd-registration"
          cost-center = "${local.env_cfg.cost_center}"
          managed-by  = "terraform"
          repo        = "infra/live/${local.path.env}/${local.path.region}/${local.path.cluster}/argocd-registration"
        }
      }
    }
  EOT
}

inputs = {
  cluster_region      = local.path.region
  controller_role_arn = "arn:aws:iam::${local.env_cfg.account_id}:role/${local.prefix}-${local.path.env}-argocd-controller"
  reader_role_arn     = "arn:aws:iam::${local.ss}:role/${local.prefix}-shared-services-${local.short[local.working]}-central-external-secrets"
  writer_role_arn     = "arn:aws:iam::${local.ss}:role/${local.prefix}-shared-services-argocd-registration"
  # Vault (central cluster of shared-services) configures the jwt auth mount of this cluster from the registration
  vault_bootstrap_role_arn = "arn:aws:iam::${local.ss}:role/${local.prefix}-shared-services-${local.short[local.working]}-vault-bootstrap"
  tags = {
    team        = "platform"
    owner       = local.env_cfg.owner
    pci-scope   = "connected"
    data-class  = "internal"
    backup-tier = "none"
  }
}
