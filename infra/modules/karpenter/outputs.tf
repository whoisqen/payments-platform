output "manifests" {
  value = merge(
    { for name, c in local.ec2_node_classes : "ec2nodeclass-${name}.yaml" => yamlencode(c) },
    { for name, p in local.node_pools : "nodepool-${name}.yaml" => yamlencode(p) },
  )
  description = "EC2NodeClass and NodePool manifests by file name, for the ArgoCD platform application; the Karpenter CRDs are not applied from Terraform."
}

output "node_role_arn" {
  value       = aws_iam_role.node.arn
  description = "Node role of every Karpenter node."
}

output "controller_role_arn" {
  value       = aws_iam_role.controller.arn
  description = "Pod identity role of the Karpenter controller."
}

output "interruption_queue_name" {
  value       = aws_sqs_queue.interruption.name
  description = "Queue name for the Karpenter settings of the Helm values."
}
