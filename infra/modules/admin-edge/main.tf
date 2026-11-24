data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

locals {
  name         = "${var.name_prefix}-${var.environment}"
  wildcard     = "*.${var.zone_name}"
  account_id   = data.aws_caller_identity.current.account_id
  partition    = data.aws_partition.current.partition
  signing_algo = startswith(var.ca_key_algorithm, "RSA") ? "SHA256WITHRSA" : "SHA256WITHECDSA"

  roles = {
    load-balancer-controller = var.load_balancer_controller
    privateca-issuer         = var.privateca_issuer
  }
}

# ---------------------------------------------------------------------------
# Private zone and the wildcard record to the internal NLB
# ---------------------------------------------------------------------------

resource "aws_route53_zone" "admin" {
  name    = var.zone_name
  comment = "Admin tools, reached only through the internal gateway"

  dynamic "vpc" {
    for_each = toset(var.vpc_ids)
    content {
      vpc_id = vpc.value
    }
  }

  tags = var.tags
}

# The NLB belongs to the load balancer controller, which builds it from the Gateway; it exists only after the first apply and the sync of the Gateway.
data "aws_lb" "gateway" {
  count = var.nlb_lookup_enabled ? 1 : 0

  tags = {
    "service.k8s.aws/stack" = var.nlb_stack_tag
  }

  lifecycle {
    precondition {
      condition     = var.nlb_stack_tag != null
      error_message = "nlb_stack_tag is required when nlb_lookup_enabled is true."
    }
  }
}

resource "aws_route53_record" "wildcard" {
  count = var.nlb_lookup_enabled ? 1 : 0

  zone_id = aws_route53_zone.admin.zone_id
  name    = local.wildcard
  type    = "A"

  alias {
    name                   = data.aws_lb.gateway[0].dns_name
    zone_id                = data.aws_lb.gateway[0].zone_id
    evaluate_target_health = true
  }
}

# ---------------------------------------------------------------------------
# Private CA (root) for the zone; the key stays in the AWS managed HSM of the service. Revocation is off: certificates are short-lived.
# ---------------------------------------------------------------------------

resource "aws_acmpca_certificate_authority" "root" {
  type                            = "ROOT"
  usage_mode                      = "SHORT_LIVED_CERTIFICATE"
  key_storage_security_standard   = "FIPS_140_2_LEVEL_3_OR_HIGHER"
  permanent_deletion_time_in_days = 30

  certificate_authority_configuration {
    key_algorithm     = var.ca_key_algorithm
    signing_algorithm = local.signing_algo

    subject {
      organization = var.ca_organization
      common_name  = "${local.name} admin root CA"
    }
  }

  revocation_configuration {
    crl_configuration {
      enabled = false
    }
  }

  tags = var.tags
}

resource "aws_acmpca_certificate" "root" {
  certificate_authority_arn   = aws_acmpca_certificate_authority.root.arn
  certificate_signing_request = aws_acmpca_certificate_authority.root.certificate_signing_request
  signing_algorithm           = local.signing_algo
  template_arn                = "arn:${local.partition}:acm-pca:::template/RootCACertificate/V1"

  validity {
    type  = "YEARS"
    value = var.ca_validity_years
  }
}

resource "aws_acmpca_certificate_authority_certificate" "root" {
  certificate_authority_arn = aws_acmpca_certificate_authority.root.arn
  certificate               = aws_acmpca_certificate.root.certificate
  certificate_chain         = aws_acmpca_certificate.root.certificate_chain
}

# ---------------------------------------------------------------------------
# Pod Identity roles
# ---------------------------------------------------------------------------

resource "aws_iam_role" "this" {
  for_each = local.roles

  name                 = "${local.name}-${each.key}-pod"
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

resource "aws_eks_pod_identity_association" "this" {
  for_each = local.roles

  cluster_name    = var.cluster_name
  namespace       = each.value.namespace
  service_account = each.value.service_account
  role_arn        = aws_iam_role.this[each.key].arn

  tags = var.tags
}

# The issuer signs with this CA and nothing else.
resource "aws_iam_role_policy" "privateca_issuer" {
  name = "issue-from-admin-ca"
  role = aws_iam_role.this["privateca-issuer"].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "IssueFromTheCa"
      Effect   = "Allow"
      Action   = ["acm-pca:IssueCertificate", "acm-pca:GetCertificate", "acm-pca:DescribeCertificateAuthority"]
      Resource = [aws_acmpca_certificate_authority.root.arn]
    }]
  })
}

# The standard controller policy, with every write limited to resources of this cluster (tag elbv2.k8s.aws/cluster).
resource "aws_iam_role_policy" "load_balancer_controller" {
  name = "load-balancer-controller"
  role = aws_iam_role.this["load-balancer-controller"].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ServiceLinkedRole"
        Effect   = "Allow"
        Action   = ["iam:CreateServiceLinkedRole"]
        Resource = "*"
        Condition = {
          StringEquals = { "iam:AWSServiceName" = "elasticloadbalancing.amazonaws.com" }
        }
      },
      {
        Sid    = "Describe"
        Effect = "Allow"
        Action = [
          "ec2:DescribeAccountAttributes", "ec2:DescribeAddresses", "ec2:DescribeAvailabilityZones",
          "ec2:DescribeInternetGateways", "ec2:DescribeVpcs", "ec2:DescribeVpcPeeringConnections",
          "ec2:DescribeSubnets", "ec2:DescribeSecurityGroups", "ec2:DescribeInstances",
          "ec2:DescribeNetworkInterfaces", "ec2:DescribeTags", "ec2:GetCoipPoolUsage", "ec2:DescribeCoipPools",
          "ec2:GetSecurityGroupsForVpc", "ec2:DescribeIpamPools", "ec2:DescribeRouteTables",
          "elasticloadbalancing:DescribeLoadBalancers", "elasticloadbalancing:DescribeLoadBalancerAttributes",
          "elasticloadbalancing:DescribeListeners", "elasticloadbalancing:DescribeListenerCertificates",
          "elasticloadbalancing:DescribeSSLPolicies", "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:DescribeTargetGroups", "elasticloadbalancing:DescribeTargetGroupAttributes",
          "elasticloadbalancing:DescribeTargetHealth", "elasticloadbalancing:DescribeTags",
          "elasticloadbalancing:DescribeTrustStores", "elasticloadbalancing:DescribeListenerAttributes",
          "elasticloadbalancing:DescribeCapacityReservation",
        ]
        Resource = "*"
      },
      {
        Sid      = "SecurityGroupRules"
        Effect   = "Allow"
        Action   = ["ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress"]
        Resource = "arn:${local.partition}:ec2:*:${local.account_id}:security-group/*"
        Condition = {
          Null = { "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false" }
        }
      },
      {
        Sid      = "CreateSecurityGroup"
        Effect   = "Allow"
        Action   = ["ec2:CreateSecurityGroup"]
        Resource = "*"
        Condition = {
          StringEquals = { "aws:RequestTag/elbv2.k8s.aws/cluster" = var.cluster_name }
        }
      },
      {
        Sid      = "TagSecurityGroupOnCreate"
        Effect   = "Allow"
        Action   = ["ec2:CreateTags"]
        Resource = "arn:${local.partition}:ec2:*:${local.account_id}:security-group/*"
        Condition = {
          StringEquals = { "ec2:CreateAction" = "CreateSecurityGroup" }
          Null         = { "aws:RequestTag/elbv2.k8s.aws/cluster" = "false" }
        }
      },
      {
        Sid      = "DeleteSecurityGroup"
        Effect   = "Allow"
        Action   = ["ec2:CreateTags", "ec2:DeleteTags", "ec2:DeleteSecurityGroup"]
        Resource = "arn:${local.partition}:ec2:*:${local.account_id}:security-group/*"
        Condition = {
          StringEquals = { "aws:ResourceTag/elbv2.k8s.aws/cluster" = var.cluster_name }
        }
      },
      {
        Sid    = "CreateLoadBalancerAndTargetGroup"
        Effect = "Allow"
        Action = ["elasticloadbalancing:CreateLoadBalancer", "elasticloadbalancing:CreateTargetGroup"]
        Resource = [
          "arn:${local.partition}:elasticloadbalancing:*:${local.account_id}:loadbalancer/*",
          "arn:${local.partition}:elasticloadbalancing:*:${local.account_id}:targetgroup/*",
        ]
        Condition = {
          StringEquals = { "aws:RequestTag/elbv2.k8s.aws/cluster" = var.cluster_name }
        }
      },
      {
        Sid    = "ListenersAndRules"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:CreateListener", "elasticloadbalancing:DeleteListener",
          "elasticloadbalancing:CreateRule", "elasticloadbalancing:DeleteRule",
        ]
        Resource = [
          "arn:${local.partition}:elasticloadbalancing:*:${local.account_id}:listener/net/*/*/*",
          "arn:${local.partition}:elasticloadbalancing:*:${local.account_id}:listener/app/*/*/*",
          "arn:${local.partition}:elasticloadbalancing:*:${local.account_id}:listener-rule/net/*/*/*",
          "arn:${local.partition}:elasticloadbalancing:*:${local.account_id}:listener-rule/app/*/*/*",
        ]
      },
      {
        Sid    = "TagOwnLoadBalancersAndTargetGroups"
        Effect = "Allow"
        Action = ["elasticloadbalancing:AddTags", "elasticloadbalancing:RemoveTags"]
        Resource = [
          "arn:${local.partition}:elasticloadbalancing:*:${local.account_id}:targetgroup/*/*",
          "arn:${local.partition}:elasticloadbalancing:*:${local.account_id}:loadbalancer/net/*/*",
          "arn:${local.partition}:elasticloadbalancing:*:${local.account_id}:loadbalancer/app/*/*",
        ]
        Condition = {
          StringEquals = { "aws:ResourceTag/elbv2.k8s.aws/cluster" = var.cluster_name }
        }
      },
      {
        Sid    = "TagOnCreate"
        Effect = "Allow"
        Action = ["elasticloadbalancing:AddTags"]
        Resource = [
          "arn:${local.partition}:elasticloadbalancing:*:${local.account_id}:targetgroup/*/*",
          "arn:${local.partition}:elasticloadbalancing:*:${local.account_id}:loadbalancer/net/*/*",
          "arn:${local.partition}:elasticloadbalancing:*:${local.account_id}:loadbalancer/app/*/*",
        ]
        Condition = {
          StringEquals = { "elasticloadbalancing:CreateAction" = ["CreateTargetGroup", "CreateLoadBalancer"] }
          Null         = { "aws:RequestTag/elbv2.k8s.aws/cluster" = "false" }
        }
      },
      {
        Sid    = "ModifyOwnLoadBalancers"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:ModifyLoadBalancerAttributes", "elasticloadbalancing:SetIpAddressType",
          "elasticloadbalancing:SetSecurityGroups", "elasticloadbalancing:SetSubnets",
          "elasticloadbalancing:DeleteLoadBalancer", "elasticloadbalancing:ModifyTargetGroup",
          "elasticloadbalancing:ModifyTargetGroupAttributes", "elasticloadbalancing:DeleteTargetGroup",
          "elasticloadbalancing:ModifyListenerAttributes", "elasticloadbalancing:ModifyCapacityReservation",
          "elasticloadbalancing:ModifyIpPools",
        ]
        Resource = [
          "arn:${local.partition}:elasticloadbalancing:*:${local.account_id}:loadbalancer/*",
          "arn:${local.partition}:elasticloadbalancing:*:${local.account_id}:targetgroup/*",
        ]
        Condition = {
          StringEquals = { "aws:ResourceTag/elbv2.k8s.aws/cluster" = var.cluster_name }
        }
      },
      {
        Sid      = "Targets"
        Effect   = "Allow"
        Action   = ["elasticloadbalancing:RegisterTargets", "elasticloadbalancing:DeregisterTargets"]
        Resource = "arn:${local.partition}:elasticloadbalancing:*:${local.account_id}:targetgroup/*/*"
      },
      {
        Sid    = "ListenerChanges"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:SetWebAcl", "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:AddListenerCertificates", "elasticloadbalancing:RemoveListenerCertificates",
          "elasticloadbalancing:ModifyRule", "elasticloadbalancing:SetRulePriorities",
        ]
        Resource = [
          "arn:${local.partition}:elasticloadbalancing:*:${local.account_id}:loadbalancer/*",
          "arn:${local.partition}:elasticloadbalancing:*:${local.account_id}:listener/net/*/*/*",
          "arn:${local.partition}:elasticloadbalancing:*:${local.account_id}:listener/app/*/*/*",
          "arn:${local.partition}:elasticloadbalancing:*:${local.account_id}:listener-rule/net/*/*/*",
          "arn:${local.partition}:elasticloadbalancing:*:${local.account_id}:listener-rule/app/*/*/*",
        ]
      },
    ]
  })
}
