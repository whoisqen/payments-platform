output "oidc_provider_arn" {
  value       = local.provider_arn
  description = "GitHub OIDC provider used by the roles."
}

output "plan_role_arn" {
  value       = aws_iam_role.plan.arn
  description = "Role for plan on pull requests."
}

output "apply_role_arns" {
  value       = { for k, r in aws_iam_role.apply : k => r.arn }
  description = "Apply roles by component."
}

output "ecr_read_role_arn" {
  value       = one(aws_iam_role.ecr_read[*].arn)
  description = "Read-only registry role (repository variable AWS_ROLE_ECR_READ); null when no repositories are given."
}
