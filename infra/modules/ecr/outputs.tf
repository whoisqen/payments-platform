output "repository_urls" {
  value       = { for k, r in aws_ecr_repository.this : k => r.repository_url }
  description = "Repository URLs by short name."
}

output "repository_arns" {
  value       = { for k, r in aws_ecr_repository.this : k => r.arn }
  description = "Repository ARNs by short name."
}
