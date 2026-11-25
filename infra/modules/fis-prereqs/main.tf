locals {
  name     = "${var.name_prefix}-${var.environment}-${var.region_short}"
  env      = "${var.name_prefix}-${var.environment}"
  arn_base = "${var.region}:${var.account_id}"
  env_tag  = { StringEquals = { "aws:ResourceTag/environment" = var.environment } }

  # Role names fis-experiments derives from the same prefix; the access entry and PassRole need them before that unit exists.
  fis_role_arn        = "arn:aws:iam::${var.account_id}:role/${local.name}-fis-experiment"
  automation_role_arn = "arn:aws:iam::${var.account_id}:role/${local.name}-chaos-automation"
  chaos_documents     = "${local.env}-chaos-*"

  # Boundary of the FIS and automation roles: the union of both inline policies, never a stricter condition than theirs.
  boundary_statements = [
    {
      Sid       = "NodesOfThisEnvironment"
      Effect    = "Allow"
      Action    = ["ec2:TerminateInstances", "ec2:StopInstances", "ec2:StartInstances", "ec2:SendSpotInstanceInterruptions"]
      Resource  = "arn:aws:ec2:${local.arn_base}:instance/*"
      Condition = local.env_tag
    },
    {
      Sid       = "AuroraOfThisEnvironment"
      Effect    = "Allow"
      Action    = ["rds:FailoverDBCluster", "rds:RebootDBInstance"]
      Resource  = ["arn:aws:rds:${local.arn_base}:cluster:*", "arn:aws:rds:${local.arn_base}:db:*"]
      Condition = local.env_tag
    },
    {
      Sid       = "CreateFisNetworkAcl"
      Effect    = "Allow"
      Action    = ["ec2:CreateNetworkAcl"]
      Resource  = "arn:aws:ec2:${local.arn_base}:network-acl/*"
      Condition = { StringEquals = { "aws:RequestTag/managedByFIS" = "true" } }
    },
    {
      Sid       = "CreateFisNetworkAclInVpc"
      Effect    = "Allow"
      Action    = ["ec2:CreateNetworkAcl"]
      Resource  = "arn:aws:ec2:${local.arn_base}:vpc/*"
      Condition = local.env_tag
    },
    {
      Sid       = "TagFisNetworkAcl"
      Effect    = "Allow"
      Action    = ["ec2:CreateTags"]
      Resource  = "arn:aws:ec2:${local.arn_base}:network-acl/*"
      Condition = { StringEquals = { "ec2:CreateAction" = "CreateNetworkAcl" } }
    },
    {
      Sid       = "ManageFisNetworkAcl"
      Effect    = "Allow"
      Action    = ["ec2:CreateNetworkAclEntry", "ec2:DeleteNetworkAclEntry", "ec2:DeleteNetworkAcl"]
      Resource  = "arn:aws:ec2:${local.arn_base}:network-acl/*"
      Condition = { StringEquals = { "aws:ResourceTag/managedByFIS" = "true" } }
    },
    {
      Sid       = "SwapAclOfSubnetsOfThisEnvironment"
      Effect    = "Allow"
      Action    = ["ec2:ReplaceNetworkAclAssociation"]
      Resource  = "arn:aws:ec2:${local.arn_base}:subnet/*"
      Condition = local.env_tag
    },
    {
      # The original ACL restored at the end carries no managedByFIS tag.
      Sid      = "SwapAclAssociation"
      Effect   = "Allow"
      Action   = ["ec2:ReplaceNetworkAclAssociation"]
      Resource = "arn:aws:ec2:${local.arn_base}:network-acl/*"
    },
    {
      Sid    = "ResolveTargets"
      Effect = "Allow"
      Action = [
        "ec2:DescribeInstances", "ec2:DescribeSubnets", "ec2:DescribeNetworkAcls", "ec2:DescribeVpcs", "ec2:DescribeManagedPrefixLists",
        "ec2:GetManagedPrefixListEntries", "ec2:DescribeVpcPeeringConnections", "ec2:DescribeTransitGatewayAttachments",
        "ec2:DescribeVpcEndpoints", "rds:DescribeDBClusters", "rds:DescribeDBInstances", "tag:GetResources",
      ]
      Resource = "*"
    },
    {
      Sid      = "MemoryDbOfThisEnvironment"
      Effect   = "Allow"
      Action   = ["memorydb:FailoverShard", "memorydb:DescribeClusters"]
      Resource = "arn:aws:memorydb:${local.arn_base}:cluster/${local.env}-*"
    },
    {
      Sid      = "FindMskCluster"
      Effect   = "Allow"
      Action   = ["kafka:ListClustersV2"]
      Resource = "*"
    },
    {
      Sid      = "MskOfThisEnvironment"
      Effect   = "Allow"
      Action   = ["kafka:RebootBroker", "kafka:DescribeClusterV2"]
      Resource = "arn:aws:kafka:${local.arn_base}:cluster/${local.env}-*/*"
    },
    {
      Sid    = "StartChaosAutomation"
      Effect = "Allow"
      Action = ["ssm:StartAutomationExecution"]
      Resource = [
        "arn:aws:ssm:${local.arn_base}:document/${local.chaos_documents}",
        "arn:aws:ssm:${local.arn_base}:automation-definition/${local.chaos_documents}:*",
      ]
    },
    {
      Sid      = "FollowAutomation"
      Effect   = "Allow"
      Action   = ["ssm:GetAutomationExecution", "ssm:StopAutomationExecution"]
      Resource = "arn:aws:ssm:${local.arn_base}:automation-execution/*"
    },
    {
      Sid    = "SendChaosCommands"
      Effect = "Allow"
      Action = ["ssm:SendCommand"]
      Resource = [
        "arn:aws:ssm:${local.arn_base}:document/${local.chaos_documents}",
        "arn:aws:ssm:${var.region}::document/AWSFIS-Run-*",
      ]
    },
    {
      Sid       = "SendCommandsToNodesOfThisEnvironment"
      Effect    = "Allow"
      Action    = ["ssm:SendCommand"]
      Resource  = "arn:aws:ec2:${local.arn_base}:instance/*"
      Condition = local.env_tag
    },
    {
      Sid      = "FollowCommands"
      Effect   = "Allow"
      Action   = ["ssm:ListCommands", "ssm:CancelCommand"]
      Resource = "*"
    },
    {
      Sid       = "PassAutomationRole"
      Effect    = "Allow"
      Action    = ["iam:PassRole"]
      Resource  = local.automation_role_arn
      Condition = { StringEquals = { "iam:PassedToService" = "ssm.amazonaws.com" } }
    },
    {
      Sid      = "DescribeClustersOfThisEnvironment"
      Effect   = "Allow"
      Action   = ["eks:DescribeCluster"]
      Resource = "arn:aws:eks:${local.arn_base}:cluster/${local.env}-*"
    },
    {
      Sid      = "ExperimentLogDelivery"
      Effect   = "Allow"
      Action   = ["logs:CreateLogDelivery", "logs:PutResourcePolicy", "logs:DescribeResourcePolicies", "logs:DescribeLogGroups"]
      Resource = "*"
    },
  ]
}

resource "aws_iam_policy" "boundary" {
  name        = var.boundary_name
  path        = "/"
  description = "Permissions boundary of the FIS experiment and chaos automation roles of ${var.environment}."
  policy      = jsonencode({ Version = "2012-10-17", Statement = local.boundary_statements })
  tags        = merge(var.tags, { Name = var.boundary_name })
}

# Pod actions authenticate as this Kubernetes user; namespace RBAC binds it (deploy task, see README).
resource "aws_eks_access_entry" "fis" {
  count = var.eks_access_entry == null ? 0 : 1

  cluster_name      = var.eks_access_entry.cluster_name
  principal_arn     = local.fis_role_arn
  type              = "STANDARD"
  user_name         = var.eks_access_entry.username
  kubernetes_groups = []
  tags              = merge(var.tags, { Name = "${local.name}-fis-experiment" })
}
