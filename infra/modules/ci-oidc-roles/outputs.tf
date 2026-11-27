output "oidc_provider_arn" {
  value       = local.provider_arn
  description = "GitHub OIDC provider used by the roles."
}

output "plan_role_arn" {
  value       = aws_iam_role.plan.arn
  description = "Read-only plan role of the nightly drift check on main."
}

output "apply_role_arns" {
  value       = { for k, r in aws_iam_role.apply : k => r.arn }
  description = "Apply roles by component."
}

output "ecr_read_role_arn" {
  value       = one(aws_iam_role.ecr_read[*].arn)
  description = "Read-only registry role (repository variable AWS_ROLE_ECR_READ); null when no repositories are given."
}

output "dr_apply_role_arn" {
  value       = one(aws_iam_role.dr_apply[*].arn)
  description = "Role of the region switch (vars.AWS_ROLE_DR_APPLY of the dr-compute-<env> environment; bootstrap dr_apply_role_arns); null without dr_apply."
}
