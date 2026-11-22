output "cluster_arn" {
  description = "ARN of the cluster; the AWS Backup tag selection also finds it by backup-tier."
  value       = aws_memorydb_cluster.this.arn
}

output "cluster_endpoint" {
  description = "Cluster configuration endpoint."
  value       = aws_memorydb_cluster.this.cluster_endpoint
}

output "acl_name" {
  description = "ACL attached to the cluster."
  value       = aws_memorydb_acl.this.name
}
