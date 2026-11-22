locals {
  cluster_arn   = "arn:aws:eks:${var.region}:${var.account_id}:cluster/${var.cluster_name}"
  node_role     = "${var.cluster_name}-node"
  node_role_arn = "arn:aws:iam::${var.account_id}:role/${local.node_role}"
  queue_arn     = aws_sqs_queue.interruption.arn
  owned_tag     = "kubernetes.io/cluster/${var.cluster_name}"

  node_tags = merge(var.extra_node_tags, var.tags, { "karpenter.sh/discovery" = var.cluster_name })

  # Bottlerocket settings of section 26.1; the admin container stays off and the control container is the SSM path.
  user_data = <<-EOT
    [settings.kernel]
    lockdown = "integrity"
    [settings.host-containers.admin]
    enabled = false
    [settings.host-containers.control]
    enabled = true
  EOT

  # Payment pools never use Spot: an interrupted pod in the middle of a PSP call leaves the payment in the unknown state.
  # ci and ci-prod exist only in the shared-services cluster (enabled_pools); a payments cluster never gets them.
  all_pools = {
    payments = { taint = "payments", capacity = ["on-demand"], expire = "336h", grace = "30m", consolidation = "WhenEmpty" }
    stateful = { taint = "stateful", capacity = ["on-demand"], expire = "336h", grace = "30m", consolidation = "WhenEmpty" }
    cde      = { taint = "cde", capacity = ["on-demand"], expire = "336h", grace = "30m", consolidation = "WhenEmpty" }
    workers  = { taint = "workers", capacity = ["spot", "on-demand"], expire = "168h", grace = "90s", consolidation = "WhenEmptyOrUnderutilized" }
    # Runner pods are never consolidated mid-job; ci-prod stays On-Demand so a release job is not lost to a Spot interruption.
    ci      = { taint = "ci", scope = "none", capacity = ["spot", "on-demand"], expire = "168h", grace = "10m", consolidation = "WhenEmpty" }
    ci-prod = { taint = "ci-prod", scope = "none", capacity = ["on-demand"], expire = "168h", grace = "1h", consolidation = "WhenEmpty" }
    # Untrusted pull request code gets nodes of its own, never shared with ci-stage pods that hold IRSA tokens.
    ci-pr = { taint = "ci-pr", scope = "none", capacity = ["spot", "on-demand"], expire = "168h", grace = "10m", consolidation = "WhenEmpty" }
  }
  pools = { for name, p in local.all_pools : name => merge({ scope = "cde" }, p) if contains(var.enabled_pools, name) }

  ec2_node_class = {
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata   = { name = "hardened" }
    spec = {
      role                       = local.node_role
      amiSelectorTerms           = [{ alias = "bottlerocket@${var.bottlerocket_version}" }]
      subnetSelectorTerms        = [for s in var.subnet_ids : { id = s }]
      securityGroupSelectorTerms = [for s in var.security_group_ids : { id = s }]
      associatePublicIPAddress   = false
      kubelet                    = { maxPods = var.max_pods }
      userData                   = local.user_data
      tags                       = local.node_tags
      metadataOptions = {
        httpEndpoint            = "enabled"
        httpTokens              = "required"
        httpPutResponseHopLimit = 1
      }
      blockDeviceMappings = [
        {
          deviceName = "/dev/xvda"
          ebs        = { volumeSize = "4Gi", volumeType = "gp3", encrypted = true, kmsKeyID = var.ebs_kms_key_arn, deleteOnTermination = true }
        },
        {
          deviceName = "/dev/xvdb"
          ebs        = { volumeSize = "80Gi", volumeType = "gp3", encrypted = true, kmsKeyID = var.ebs_kms_key_arn, deleteOnTermination = true }
        },
      ]
    }
  }

  node_pools = { for name, p in local.pools : name => {
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata   = { name = name }
    spec = {
      limits = { cpu = tostring(var.cpu_limits[name]) }
      template = {
        metadata = { labels = { workload = p.taint, "platform.io/pci-scope" = p.scope } }
        spec = {
          nodeClassRef           = { group = "karpenter.k8s.aws", kind = "EC2NodeClass", name = "hardened" }
          taints                 = [{ key = "workload", value = p.taint, effect = "NoSchedule" }]
          expireAfter            = p.expire
          terminationGracePeriod = p.grace
          requirements = [
            { key = "kubernetes.io/os", operator = "In", values = ["linux"] },
            { key = "kubernetes.io/arch", operator = "In", values = ["arm64", "amd64"] },
            { key = "karpenter.sh/capacity-type", operator = "In", values = p.capacity },
            { key = "karpenter.k8s.aws/instance-family", operator = "In", values = var.instance_families[name] },
            { key = "karpenter.k8s.aws/instance-size", operator = "NotIn", values = ["metal", "nano", "micro", "small"] },
          ]
        }
      }
      # Outside 02:00-06:00 UTC only expiry may replace a node; inside it at most 10% at a time.
      disruption = {
        consolidationPolicy = p.consolidation
        consolidateAfter    = "5m"
        budgets = [
          { nodes = "10%" },
          { nodes = "0", reasons = ["Drifted", "Underutilized", "Empty"], schedule = "0 6 * * *", duration = "20h" },
        ]
      }
    }
  } }
}

resource "aws_sqs_queue" "interruption" {
  name                      = var.cluster_name
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true
  tags                      = var.tags
}

resource "aws_sqs_queue_policy" "interruption" {
  queue_url = aws_sqs_queue.interruption.url
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EventBridgeAndSqsSend"
        Effect    = "Allow"
        Principal = { Service = ["events.amazonaws.com", "sqs.amazonaws.com"] }
        Action    = "sqs:SendMessage"
        Resource  = local.queue_arn
      },
      {
        Sid       = "TlsOnly"
        Effect    = "Deny"
        Principal = "*"
        Action    = "sqs:*"
        Resource  = local.queue_arn
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
    ]
  })
}

resource "aws_cloudwatch_event_rule" "interruption" {
  for_each = {
    spot-interruption = { source = "aws.ec2", type = "EC2 Spot Instance Interruption Warning" }
    rebalance         = { source = "aws.ec2", type = "EC2 Instance Rebalance Recommendation" }
    state-change      = { source = "aws.ec2", type = "EC2 Instance State-change Notification" }
    health            = { source = "aws.health", type = "AWS Health Event" }
  }

  name          = "${var.cluster_name}-${each.key}"
  event_pattern = jsonencode({ source = [each.value.source], "detail-type" = [each.value.type] })
  tags          = var.tags
}

resource "aws_cloudwatch_event_target" "interruption" {
  for_each = aws_cloudwatch_event_rule.interruption

  rule = each.value.name
  arn  = local.queue_arn
}

resource "aws_iam_role" "node" {
  name                 = local.node_role
  permissions_boundary = var.permissions_boundary_arn
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = var.tags
}

# Image pull, node registration and Session Manager only; no s3, secretsmanager, kms or iam (section 26.3).
resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ])

  role       = aws_iam_role.node.name
  policy_arn = each.value
}

resource "aws_eks_access_entry" "node" {
  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.node.arn
  type          = "EC2_LINUX"
  tags          = var.tags
}

resource "aws_iam_role" "controller" {
  name                 = "${var.cluster_name}-karpenter"
  permissions_boundary = var.permissions_boundary_arn
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "controller" {
  name = "karpenter"
  role = aws_iam_role.controller.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "LaunchFromSharedResources"
        Effect = "Allow"
        Action = ["ec2:RunInstances", "ec2:CreateFleet"]
        Resource = [
          "arn:aws:ec2:${var.region}::image/*",
          "arn:aws:ec2:${var.region}::snapshot/*",
          "arn:aws:ec2:${var.region}:${var.account_id}:security-group/*",
          "arn:aws:ec2:${var.region}:${var.account_id}:subnet/*",
          "arn:aws:ec2:${var.region}:${var.account_id}:capacity-reservation/*",
        ]
      },
      {
        Sid      = "LaunchFromOwnTemplates"
        Effect   = "Allow"
        Action   = ["ec2:RunInstances", "ec2:CreateFleet"]
        Resource = "arn:aws:ec2:${var.region}:${var.account_id}:launch-template/*"
        Condition = {
          StringEquals = { "aws:ResourceTag/${local.owned_tag}" = "owned" }
          StringLike   = { "aws:ResourceTag/karpenter.sh/nodepool" = "*" }
        }
      },
      {
        Sid    = "CreateTaggedInstances"
        Effect = "Allow"
        Action = ["ec2:RunInstances", "ec2:CreateFleet", "ec2:CreateLaunchTemplate"]
        Resource = [
          "arn:aws:ec2:${var.region}:${var.account_id}:fleet/*",
          "arn:aws:ec2:${var.region}:${var.account_id}:instance/*",
          "arn:aws:ec2:${var.region}:${var.account_id}:volume/*",
          "arn:aws:ec2:${var.region}:${var.account_id}:network-interface/*",
          "arn:aws:ec2:${var.region}:${var.account_id}:launch-template/*",
          "arn:aws:ec2:${var.region}:${var.account_id}:spot-instances-request/*",
        ]
        Condition = {
          StringEquals = {
            "aws:RequestTag/${local.owned_tag}"   = "owned"
            "aws:RequestTag/eks:eks-cluster-name" = var.cluster_name
          }
          StringLike = { "aws:RequestTag/karpenter.sh/nodepool" = "*" }
        }
      },
      {
        Sid    = "TagOnCreate"
        Effect = "Allow"
        Action = "ec2:CreateTags"
        Resource = [
          "arn:aws:ec2:${var.region}:${var.account_id}:fleet/*",
          "arn:aws:ec2:${var.region}:${var.account_id}:instance/*",
          "arn:aws:ec2:${var.region}:${var.account_id}:volume/*",
          "arn:aws:ec2:${var.region}:${var.account_id}:network-interface/*",
          "arn:aws:ec2:${var.region}:${var.account_id}:launch-template/*",
          "arn:aws:ec2:${var.region}:${var.account_id}:spot-instances-request/*",
        ]
        Condition = {
          StringEquals = {
            "aws:RequestTag/${local.owned_tag}"   = "owned"
            "aws:RequestTag/eks:eks-cluster-name" = var.cluster_name
            "ec2:CreateAction"                    = ["RunInstances", "CreateFleet", "CreateLaunchTemplate"]
          }
          StringLike = { "aws:RequestTag/karpenter.sh/nodepool" = "*" }
        }
      },
      {
        Sid      = "TagOwnInstances"
        Effect   = "Allow"
        Action   = "ec2:CreateTags"
        Resource = "arn:aws:ec2:${var.region}:${var.account_id}:instance/*"
        Condition = {
          StringEquals = { "aws:ResourceTag/eks:eks-cluster-name" = var.cluster_name }
          StringLike   = { "aws:ResourceTag/karpenter.sh/nodepool" = "*" }
        }
      },
      {
        Sid    = "DeleteOwnInstancesAndTemplates"
        Effect = "Allow"
        Action = ["ec2:TerminateInstances", "ec2:DeleteLaunchTemplate"]
        Resource = [
          "arn:aws:ec2:${var.region}:${var.account_id}:instance/*",
          "arn:aws:ec2:${var.region}:${var.account_id}:launch-template/*",
        ]
        Condition = {
          StringEquals = { "aws:ResourceTag/${local.owned_tag}" = "owned" }
          StringLike   = { "aws:ResourceTag/karpenter.sh/nodepool" = "*" }
        }
      },
      {
        # Ec2 Describe* actions do not support resource-level permissions; the region condition is the only scope.
        Sid    = "DescribeCapacity"
        Effect = "Allow"
        Action = [
          "ec2:DescribeAvailabilityZones", "ec2:DescribeImages", "ec2:DescribeInstances", "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeInstanceTypes", "ec2:DescribeLaunchTemplates", "ec2:DescribeSecurityGroups", "ec2:DescribeSpotPriceHistory",
          "ec2:DescribeSubnets",
        ]
        Resource  = "*"
        Condition = { StringEquals = { "aws:RequestedRegion" = var.region } }
      },
      {
        # The EC2 pricing API does not support resource-level permissions.
        Sid      = "Pricing"
        Effect   = "Allow"
        Action   = "pricing:GetProducts"
        Resource = "*"
      },
      {
        Sid      = "ResolveBottlerocketAlias"
        Effect   = "Allow"
        Action   = "ssm:GetParameter"
        Resource = "arn:aws:ssm:${var.region}::parameter/aws/service/bottlerocket/*"
      },
      {
        Sid       = "PassNodeRole"
        Effect    = "Allow"
        Action    = "iam:PassRole"
        Resource  = local.node_role_arn
        Condition = { StringEquals = { "iam:PassedToService" = ["ec2.amazonaws.com"] } }
      },
      {
        Sid      = "DescribeOwnCluster"
        Effect   = "Allow"
        Action   = "eks:DescribeCluster"
        Resource = local.cluster_arn
      },
      {
        Sid      = "CreateInstanceProfiles"
        Effect   = "Allow"
        Action   = ["iam:CreateInstanceProfile", "iam:TagInstanceProfile"]
        Resource = "arn:aws:iam::${var.account_id}:instance-profile/*"
        Condition = {
          StringEquals = {
            "aws:RequestTag/${local.owned_tag}"            = "owned"
            "aws:RequestTag/eks:eks-cluster-name"          = var.cluster_name
            "aws:RequestTag/topology.kubernetes.io/region" = var.region
          }
          StringLike = { "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass" = "*" }
        }
      },
      {
        Sid      = "ManageOwnInstanceProfiles"
        Effect   = "Allow"
        Action   = ["iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile", "iam:DeleteInstanceProfile"]
        Resource = "arn:aws:iam::${var.account_id}:instance-profile/*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/${local.owned_tag}"            = "owned"
            "aws:ResourceTag/topology.kubernetes.io/region" = var.region
          }
          StringLike = { "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass" = "*" }
        }
      },
      {
        Sid      = "ReadInstanceProfiles"
        Effect   = "Allow"
        Action   = "iam:GetInstanceProfile"
        Resource = "arn:aws:iam::${var.account_id}:instance-profile/*"
      },
      {
        Sid      = "ReadInterruptionQueue"
        Effect   = "Allow"
        Action   = ["sqs:DeleteMessage", "sqs:GetQueueUrl", "sqs:ReceiveMessage"]
        Resource = local.queue_arn
      },
      {
        Sid      = "UseNodeVolumeKey"
        Effect   = "Allow"
        Action   = ["kms:CreateGrant", "kms:Decrypt", "kms:DescribeKey", "kms:GenerateDataKeyWithoutPlaintext", "kms:ReEncrypt*"]
        Resource = var.ebs_kms_key_arn
      },
    ]
  })
}

resource "aws_eks_pod_identity_association" "controller" {
  cluster_name    = var.cluster_name
  namespace       = "karpenter"
  service_account = "karpenter"
  role_arn        = aws_iam_role.controller.arn
  tags            = var.tags
}
