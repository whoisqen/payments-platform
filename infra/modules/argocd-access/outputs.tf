output "controller_role_arn" {
  value       = local.hub ? aws_iam_role.controller[0].arn : null
  description = "Hub: role of the Argo CD controller and server pods."
}

output "registration_writer_role_arn" {
  value       = local.hub ? aws_iam_role.writer[0].arn : null
  description = "Hub: role the eks stacks assume to write <prefix>/argocd/clusters/<name>."
}

output "spoke_role_arn" {
  value       = local.hub ? null : aws_iam_role.spoke[0].arn
  description = "Spoke: <prefix>-<env>-argocd-controller, the roleARN of every cluster registration of the environment."
}
