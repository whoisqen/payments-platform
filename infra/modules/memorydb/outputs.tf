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

output "user_names" {
  description = "MemoryDB user name of each service key; the Helm value redisUser of the service must match it."
  value       = { for k, u in aws_memorydb_user.this : k => u.user_name }
}
