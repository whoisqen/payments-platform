output "secret_arn" {
  value       = aws_secretsmanager_secret.this.arn
  description = "<prefix>/argocd/clusters/<argocd_cluster_name> in shared-services."
}

output "secret_name" {
  value       = aws_secretsmanager_secret.this.name
  description = "Name the ExternalSecret of the cluster reads."
}
