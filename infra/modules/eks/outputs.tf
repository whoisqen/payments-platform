output "cluster_name" {
  value       = aws_eks_cluster.this.name
  description = "Cluster name, pay-<env>-<region-short>-<component>."
}

output "cluster_arn" {
  value       = aws_eks_cluster.this.arn
  description = "Cluster ARN; the source ARN condition of pod identity roles."
}

output "cluster_endpoint" {
  value       = aws_eks_cluster.this.endpoint
  description = "Private API endpoint."
}

output "cluster_security_group_id" {
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  description = "Security group EKS creates for the control plane."
}

output "node_security_group_id" {
  value       = aws_security_group.node.id
  description = "Security group of Karpenter nodes; data stores admit it as a client."
}

output "oidc_provider_arn" {
  value       = aws_iam_openid_connect_provider.this.arn
  description = "IAM OIDC provider of the cluster."
}

output "oidc_issuer" {
  value       = aws_iam_openid_connect_provider.this.url
  description = "Issuer URL without scheme."
}

output "locker_pod_security_group_id" {
  value       = aws_security_group.locker_pod.id
  description = "Pod security group of the locker pods; the only client the card-vault Aurora proxy admits."
}
