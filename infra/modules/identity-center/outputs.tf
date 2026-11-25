output "permission_set_arns" {
  description = "Permission set name => ARN."
  value       = { for k, ps in aws_ssoadmin_permission_set.this : k => ps.arn }
}

output "standing_assignments" {
  description = "Keys (account/permission set/group) of the standing assignments."
  value       = keys(aws_ssoadmin_account_assignment.standing)
}

output "active_cde_grants" {
  description = "Active SRE-CDE grants: key (account/principal type/name) => expiry."
  value       = { for k, g in local.active_grants : k => g.expires_at }
}
