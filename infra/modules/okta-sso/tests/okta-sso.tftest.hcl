mock_provider "aws" {}
mock_provider "okta" {}

variables {
  name_prefix = "pay"
  okta_domain = "acme.okta.com"
  apps = {
    grafana = { label = "Grafana", redirect_uris = ["https://grafana.example.test/login/generic_oauth"], post_logout_redirect_uris = ["https://grafana.example.test/login"] }
    argocd  = { label = "Argo CD", redirect_uris = ["https://argocd.example.test/auth/callback", "http://localhost:8085/auth/callback"] }
    vault   = { label = "Vault", redirect_uris = ["https://vault.example.test/ui/vault/auth/oidc/oidc/callback", "http://localhost:8250/oidc/callback"] }
    proxy   = { label = "Admin proxy", redirect_uris = ["https://alertmanager.example.test/oauth2/callback", "https://vmui.example.test/oauth2/callback"] }
  }
  groups = {
    admin       = "pay-grafana-admins"
    sre         = "pay-sre"
    security    = "pay-security"
    engineering = "pay-engineering"
    finance     = "pay-finance"
    audit       = "pay-audit"
  }
  admin_user_ids = ["00u1owner", "00u2reserve"]
  kms_key_arn    = "arn:aws:kms:eu-central-1:222222222222:key/mrk-shared"
  tags = {
    team          = "platform"
    owner         = "platform@example.com"
    "pci-scope"   = "out-of-scope"
    "data-class"  = "internal"
    "backup-tier" = "none"
  }
}

run "one_group_per_role_and_two_administrators" {
  command = apply

  assert {
    condition     = length(okta_group.this) == 6 && okta_group.this["admin"].name == "pay-grafana-admins"
    error_message = "six groups, named from the configuration"
  }

  assert {
    condition     = length(okta_group_memberships.admins[0].users) == 2
    error_message = "the administrator group has two members"
  }

  assert {
    condition     = alltrue([for k, a in okta_app_group_assignments.this : length(a.group) == 6])
    error_message = "all six groups are assigned to every application, nobody directly"
  }
}

run "an_application_per_tool_with_pkce_and_exact_redirects" {
  command = apply

  assert {
    condition     = length(okta_app_oauth.this) == 4 && alltrue([for a in values(okta_app_oauth.this) : a.grant_types == toset(["authorization_code"]) && a.pkce_required])
    error_message = "one application per tool, authorization code flow with PKCE only"
  }

  assert {
    condition     = okta_app_oauth.this["grafana"].redirect_uris == tolist(["https://grafana.example.test/login/generic_oauth"]) && length(okta_app_oauth.this["vault"].redirect_uris) == 2
    error_message = "the redirect URIs are the callbacks of each tool"
  }

  assert {
    condition     = alltrue([for a in values(okta_app_oauth.this) : one(a.groups_claim).name == "groups" && startswith(one(a.groups_claim).value, "^(") && can(regex("pay-sre", one(a.groups_claim).value))])
    error_message = "the groups claim lists the six group names exactly"
  }
}

run "two_factors_and_phishing_resistant_for_administrators" {
  command = apply

  assert {
    condition     = okta_app_signon_policy_rule.admins.factor_mode == "2FA" && okta_app_signon_policy_rule.members.factor_mode == "2FA"
    error_message = "every rule asks for two factors"
  }

  assert {
    condition     = okta_app_signon_policy_rule.admins.priority < okta_app_signon_policy_rule.members.priority && can(regex("phishingResistant", okta_app_signon_policy_rule.admins.constraints[0]))
    error_message = "the administrator rule comes first and demands a phishing-resistant factor"
  }

  assert {
    condition     = length(okta_app_signon_policy_rule.members.groups_included) == 5
    error_message = "the member rule covers the five other groups"
  }

  assert {
    condition     = alltrue([for a in values(okta_app_oauth.this) : a.authentication_policy == okta_app_signon_policy.admin_tools.id])
    error_message = "every application uses the one admin-tools policy"
  }
}

run "a_secret_per_tool_encrypted_and_named_for_the_external_secret" {
  command = apply

  assert {
    condition     = aws_secretsmanager_secret.oidc["grafana"].name == "pay/shared-services/grafana/oidc" && aws_secretsmanager_secret.oidc["argocd"].name == "pay/shared-services/argocd/oidc"
    error_message = "the names are <prefix>/shared-services/<tool>/oidc"
  }

  assert {
    condition     = alltrue([for s in values(aws_secretsmanager_secret.oidc) : s.kms_key_id == var.kms_key_arn])
    error_message = "every secret is encrypted with the shared key"
  }

  assert {
    condition     = output.endpoints.token_url == "https://acme.okta.com/oauth2/v1/token" && output.endpoints.issuer == "https://acme.okta.com"
    error_message = "endpoints of the org authorization server"
  }
}

run "one_administrator_is_rejected" {
  command = plan

  variables {
    admin_user_ids = ["00u1owner"]
  }

  expect_failures = [var.admin_user_ids]
}

run "a_shared_group_is_rejected" {
  command = plan

  variables {
    groups = {
      admin       = "pay-sre"
      sre         = "pay-sre"
      security    = "pay-security"
      engineering = "pay-engineering"
      finance     = "pay-finance"
      audit       = "pay-audit"
    }
  }

  expect_failures = [var.groups]
}

run "a_plain_http_redirect_is_rejected" {
  command = plan

  variables {
    apps = {
      grafana = { label = "Grafana", redirect_uris = ["http://grafana.example.test/login/generic_oauth"] }
    }
  }

  expect_failures = [var.apps]
}

run "rotation_replaces_only_the_named_application" {
  command = plan

  variables {
    client_secret_rotation = { grafana = "2026-11-27" }
  }

  assert {
    condition     = terraform_data.client_secret_rotation["grafana"].input == "2026-11-27"
    error_message = "the rotation id of grafana drives its replacement"
  }
  assert {
    condition     = alltrue([for k, r in terraform_data.client_secret_rotation : k == "grafana" || r.input == "initial"])
    error_message = "other applications keep their client"
  }
}

run "rotation_of_an_unknown_application_is_rejected" {
  command = plan

  variables {
    client_secret_rotation = { unknown = "1" }
  }

  expect_failures = [var.client_secret_rotation]
}
