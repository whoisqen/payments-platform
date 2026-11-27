output "policy_arn" {
  value       = aws_iam_policy.this.arn
  description = "ARN of the boundary; equals permissions_boundary_arn of env.hcl."
}
