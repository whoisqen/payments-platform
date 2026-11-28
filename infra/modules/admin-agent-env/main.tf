locals {
  name = "${var.name_prefix}-${var.environment}-admin-agent"
}

# The admin AI agent reads one environment through this role: the Bedrock role of shared-services assumes it for each run, and
# everything it reads passes the sanitizer of tools/ai before Bedrock sees it. Read only; writes, secrets and keys are denied.
resource "aws_iam_role" "this" {
  name                 = local.name
  permissions_boundary = var.permissions_boundary_arn
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = var.admin_role_arn }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = merge(var.tags, { Name = local.name })
}

resource "aws_iam_role_policy" "this" {
  name = "admin-agent-read"
  role = aws_iam_role.this.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # _search is a POST; fine-grained access control maps this role to logs_reader_<env> (read on logs-app-<env> only)
      { Sid = "SearchLogs", Effect = "Allow", Action = ["es:ESHttpGet", "es:ESHttpPost"], Resource = ["${var.opensearch_domain_arn}/logs-app-${var.environment}/_search"] },
      {
        Sid      = "ReadNamedLogGroups"
        Effect   = "Allow"
        Action   = ["logs:FilterLogEvents", "logs:StartQuery"]
        Resource = [for g in var.log_group_names : "arn:aws:logs:${var.region}:${var.account_id}:log-group:${g}:*"]
      },
      { Sid = "QueryResults", Effect = "Allow", Action = ["logs:GetQueryResults"], Resource = "*" },
      { Sid = "DescribeClusters", Effect = "Allow", Action = ["eks:DescribeCluster"], Resource = [for c in keys(var.clusters) : "arn:aws:eks:${var.region}:${var.account_id}:cluster/${c}"] },
      { Sid = "IdentityCheck", Effect = "Allow", Action = ["sts:GetCallerIdentity"], Resource = "*" },
      { Sid = "DenySecretsAndKeys", Effect = "Deny", Action = ["secretsmanager:*", "ssm:GetParameter*", "kms:Decrypt", "kms:GenerateDataKey*"], Resource = "*" },
    ]
  })
}

# kubectl get: view only inside the allowed namespaces of each cluster; AmazonEKSViewPolicy excludes Secrets
resource "aws_eks_access_entry" "this" {
  for_each = var.clusters

  cluster_name  = each.key
  principal_arn = aws_iam_role.this.arn
  type          = "STANDARD"
  tags          = var.tags
}

resource "aws_eks_access_policy_association" "this" {
  for_each = var.clusters

  cluster_name  = each.key
  principal_arn = aws_iam_role.this.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"

  access_scope {
    type       = "namespace"
    namespaces = each.value.namespaces
  }

  depends_on = [aws_eks_access_entry.this]
}
