locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
  zone    = local.env_cfg.cfg.dns.admin_zone
  host    = { for t in ["argocd", "vault", "alertmanager", "vmui", "prometheus", "sentry"] : t => "https://${t}.${local.zone}" }
  okta    = local.env_cfg.cfg.access.okta_domain
}

terraform {
  source = "${get_repo_root()}/infra/modules//okta-sso"
}

# The Okta provider is configured here, not in the root: the API token is read from OKTA_API_TOKEN in the environment of the apply role
generate "okta_provider" {
  path      = "okta_provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOT
    provider "okta" {
      org_name = "${split(".", local.okta)[0]}"
      base_url = "${join(".", slice(split(".", local.okta), 1, length(split(".", local.okta))))}"
    }
  EOT
}

# One application per tool; the callbacks are the ones each tool defines. The proxy fronts the tools that have no sign-in of their own.
inputs = {
  okta_domain    = local.okta
  groups         = local.env_cfg.cfg.access.grafana_groups
  admin_user_ids = local.env_cfg.cfg.access.admin_user_ids
  apps = {
    grafana = {
      label                     = "Grafana"
      redirect_uris             = ["${local.env_cfg.cfg.dns.grafana_url}/login/generic_oauth"]
      post_logout_redirect_uris = ["${local.env_cfg.cfg.dns.grafana_url}/login"]
    }
    argocd = {
      label                     = "Argo CD"
      redirect_uris             = ["${local.host.argocd}/auth/callback", "http://localhost:8085/auth/callback"]
      post_logout_redirect_uris = ["${local.host.argocd}/applications"]
    }
    vault = {
      label         = "Vault"
      redirect_uris = ["${local.host.vault}/ui/vault/auth/oidc/oidc/callback", "http://localhost:8250/oidc/callback"]
    }
    proxy = {
      label         = "Admin proxy (Alertmanager, VictoriaMetrics, Prometheus)"
      redirect_uris = [for t in ["alertmanager", "vmui", "prometheus"] : "${local.host[t]}/oauth2/callback"]
    }
    sentry = {
      label         = "Sentry"
      redirect_uris = ["${local.host.sentry}/auth/sso/"]
    }
  }
  tags = {
    team        = "platform"
    owner       = local.env_cfg.owner
    pci-scope   = "out-of-scope"
    data-class  = "internal"
    backup-tier = "none"
  }
}
