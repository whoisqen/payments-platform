output "group_ids" {
  description = "Okta group id by role."
  value       = { for r, g in okta_group.this : r => g.id }
}

output "client_ids" {
  description = "Client id of each application at Okta."
  value       = { for k, a in okta_app_oauth.this : k => a.client_id }
}

output "oidc_secret_arns" {
  description = "Secret of each application that holds its OIDC client."
  value       = { for k, s in aws_secretsmanager_secret.oidc : k => s.arn }
}

output "endpoints" {
  description = "Authorization, token and userinfo endpoints and the issuer of the Okta organization."
  value       = local.endpoints
}
