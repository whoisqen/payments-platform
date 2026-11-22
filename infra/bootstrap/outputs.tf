output "state_bucket" {
  value       = aws_s3_bucket.state.id
  description = "Bucket for the backend block of every live component."
}

output "state_kms_key_arn" {
  value       = module.state_key.key_arn
  description = "Multi-Region key of the state bucket (kms_key_id of the backend)."
}

output "replica_buckets" {
  value       = { "us-east-1" = module.replica_use1.bucket_name, "us-east-2" = module.replica_use2.bucket_name }
  description = "State replicas in the recovery regions."
}

output "plan_role_arn" {
  value       = module.ci_roles.plan_role_arn
  description = "Role for plan in pull requests."
}

output "apply_role_arns" {
  value       = module.ci_roles.apply_role_arns
  description = "Apply roles by component."
}
