locals {
  region_short = { "us-east-1" = "use1" }[var.region]
  name         = "${var.name_prefix}-${var.environment}-${local.region_short}-argocd-standby"
}

# IRSA through the host cluster's OIDC provider; Argo CD signs the EKS tokens of every cluster with this identity, so no roleARN is needed.
resource "aws_iam_role" "controller" {
  name                 = local.name
  permissions_boundary = var.permissions_boundary_arn
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = var.host_cluster.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.host_cluster.oidc_issuer}:aud" = "sts.amazonaws.com"
          "${var.host_cluster.oidc_issuer}:sub" = [for sa in var.controller_service_accounts : "system:serviceaccount:${var.namespace}:${sa}"]
        }
      }
    }]
  })
  tags = merge(var.tags, { Name = local.name })
}

resource "aws_eks_access_entry" "controller" {
  for_each = var.clusters

  cluster_name  = each.value
  principal_arn = aws_iam_role.controller.arn
  type          = "STANDARD"
  tags          = var.tags
}

resource "aws_eks_access_policy_association" "controller" {
  for_each = var.clusters

  cluster_name  = each.value
  principal_arn = aws_eks_access_entry.controller[each.key].principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminPolicy"

  access_scope {
    type       = "namespace"
    namespaces = var.managed_namespaces
  }
}

# Installing CRDs and cluster roles needs cluster-admin; it is granted on the host only while installer_role_arn is set.
resource "aws_eks_access_entry" "installer" {
  count = var.installer_role_arn == null ? 0 : 1

  cluster_name  = var.host_cluster.name
  principal_arn = var.installer_role_arn
  type          = "STANDARD"
  tags          = var.tags
}

resource "aws_eks_access_policy_association" "installer" {
  count = var.installer_role_arn == null ? 0 : 1

  cluster_name  = var.host_cluster.name
  principal_arn = aws_eks_access_entry.installer[0].principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}
