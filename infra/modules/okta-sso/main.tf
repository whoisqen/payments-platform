locals {
  # The roles other than the administrators
  member_roles = [for r in keys(var.groups) : r if r != "admin"]
  endpoints = {
    auth_url  = "https://${var.okta_domain}/oauth2/v1/authorize"
    token_url = "https://${var.okta_domain}/oauth2/v1/token"
    api_url   = "https://${var.okta_domain}/oauth2/v1/userinfo"
    issuer    = "https://${var.okta_domain}"
  }
}

resource "okta_group" "this" {
  for_each = var.groups

  name        = each.value
  description = "Admin tools, role ${each.key}: each tool maps the group to its own role (tools/config/render_grafana.py for Grafana)"
}

resource "okta_group_memberships" "admins" {
  count = length(var.admin_user_ids) > 0 ? 1 : 0

  group_id = okta_group.this["admin"].id
  users    = var.admin_user_ids
}

# Two factors on every sign-in; the administrators need a phishing-resistant one. The catch-all rule that Okta adds last must stay a denial.
# One policy for every admin tool: two factors on every sign-in; the administrators need a phishing-resistant one.
# The catch-all rule that Okta adds last must stay a denial.
resource "okta_app_signon_policy" "admin_tools" {
  name        = "admin-tools"
  description = "Sign-in to the admin tools: two factors; phishing-resistant for the administrators"
}

resource "okta_app_signon_policy_rule" "admins" {
  policy_id                   = okta_app_signon_policy.admin_tools.id
  name                        = "administrators"
  priority                    = 1
  access                      = "ALLOW"
  factor_mode                 = "2FA"
  re_authentication_frequency = "PT2H"
  groups_included             = [okta_group.this["admin"].id]
  constraints                 = [jsonencode({ possession = { phishingResistant = "REQUIRED" } })]
}

resource "okta_app_signon_policy_rule" "members" {
  policy_id                   = okta_app_signon_policy.admin_tools.id
  name                        = "members"
  priority                    = 2
  access                      = "ALLOW"
  factor_mode                 = "2FA"
  re_authentication_frequency = "PT12H"
  groups_included             = [for r in local.member_roles : okta_group.this[r].id]
}

resource "okta_app_oauth" "this" {
  for_each = var.apps

  label                      = each.value.label
  type                       = "web"
  grant_types                = ["authorization_code"]
  response_types             = ["code"]
  token_endpoint_auth_method = "client_secret_basic"
  pkce_required              = each.value.pkce_required
  issuer_mode                = "ORG_URL"
  redirect_uris              = each.value.redirect_uris
  post_logout_redirect_uris  = each.value.post_logout_redirect_uris
  authentication_policy      = okta_app_signon_policy.admin_tools.id

  # Only the groups of the six roles reach a tool, as exact names
  groups_claim {
    type        = "FILTER"
    filter_type = "REGEX"
    name        = "groups"
    value       = "^(${join("|", [for g in values(var.groups) : replace(g, ".", "\\.")])})$"
  }
}

resource "okta_app_group_assignments" "this" {
  for_each = var.apps

  app_id = okta_app_oauth.this[each.key].id

  dynamic "group" {
    for_each = okta_group.this
    content {
      id = group.value.id
    }
  }
}

# Read by the ExternalSecrets of the tools; the client secrets are also in the state, which is KMS-encrypted
resource "aws_secretsmanager_secret" "oidc" {
  for_each = var.apps

  name                    = "${var.name_prefix}/${var.environment}/${each.key}/oidc"
  description             = "OIDC client of ${each.value.label} at Okta: client_id, client_secret and the endpoints"
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = var.secret_recovery_window_days
  tags                    = var.tags
}

resource "aws_secretsmanager_secret_version" "oidc" {
  for_each = var.apps

  secret_id = aws_secretsmanager_secret.oidc[each.key].id
  secret_string = jsonencode(merge(local.endpoints, {
    client_id     = okta_app_oauth.this[each.key].client_id
    client_secret = okta_app_oauth.this[each.key].client_secret
  }))
}
