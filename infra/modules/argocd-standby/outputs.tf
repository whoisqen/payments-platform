output "controller_role_arn" {
  value       = aws_iam_role.controller.arn
  description = "IRSA role of the standby Argo CD controller (service account annotation eks.amazonaws.com/role-arn)."
}

output "host_cluster_name" {
  value       = var.host_cluster.name
  description = "Cluster that runs the standby Argo CD core."
}

output "clusters" {
  value       = var.clusters
  description = "Cell => cluster name that the standby Argo CD registers (awsAuthConfig.clusterName, no roleARN)."
}
