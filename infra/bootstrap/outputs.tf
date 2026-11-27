output "state_bucket" {
  value       = aws_s3_bucket.state.id
  description = "Bucket for the backend block of every live component."
}

output "state_kms_key_arn" {
  value       = module.state_key.key_arn
  description = "Multi-Region key of the state bucket (kms_key_id of the backend)."
}

output "replica_buckets" {
  value       = { "us-east-1" = module.replica_use1.bucket_name }
  description = "State replica in the recovery region; PAY_STATE_REGION=us-east-1 makes infra/live use it."
}

output "replica_kms_key_arns" {
  value       = { "us-east-1" = module.state_key_use1.key_arn }
  description = "Replica of the state key in the recovery region (same key id as state_kms_key_arn)."
}

output "plan_role_arn" {
  value       = local.account_owner ? null : module.ci_roles[0].plan_role_arn
  description = "Plan role of this state root; null for shared-services, whose plan role is in live/shared-services/eu-central-1/ci-oidc-roles."
}

output "apply_role_arns" {
  value       = local.account_owner ? {} : merge(module.ci_roles[0].apply_role_arns, module.ci_roles[0].component_apply_role_arns)
  description = "Apply roles by component."
}

output "permissions_boundary_arn" {
  value       = local.account_owner ? module.boundary[0].policy_arn : local.boundary_arn
  description = "workload-boundary of the shared-services account."
}
