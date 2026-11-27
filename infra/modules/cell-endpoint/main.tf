locals {
  name = "${var.name_prefix}-${var.environment}-${var.region_short}-${var.cell}-endpoint"
  zone = "${var.cell}.${var.cluster_domain}"
  # The host the edge builds for a cell (deploy/charts/payments-edge): router.payments.svc.<cell>.<cluster_domain>
  host = "router.payments.svc.${local.zone}"
}

# Own subzone per cell: the edge cluster resolves the router host of each cell, nothing else of cluster_domain depends on it.
resource "aws_route53_zone" "this" {
  # checkov:skip=CKV2_AWS_38: DNSSEC signing applies to public zones only
  # checkov:skip=CKV2_AWS_39: query logging of private zones goes through the Route 53 Resolver query log of the VPC
  name    = local.zone
  comment = "Router of ${var.cell}, ${var.environment} ${var.region}: ${local.host}"

  vpc {
    vpc_id = var.vpc_id
  }

  tags = var.tags
}

resource "aws_security_group" "lb" {
  name        = local.name
  description = "Internal load balancer of the router gateway of ${var.cell}; edge nodes in, gateway pods out."
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = local.name })
}

resource "aws_vpc_security_group_ingress_rule" "lb_from_edge" {
  for_each = toset(var.client_security_group_ids)

  security_group_id            = aws_security_group.lb.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port
  description                  = "Edge gateway nodes"
}

resource "aws_vpc_security_group_egress_rule" "lb_to_gateway" {
  security_group_id            = aws_security_group.lb.id
  referenced_security_group_id = var.target_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port
  description                  = "Router gateway pods of the cell"
}

resource "aws_vpc_security_group_ingress_rule" "gateway_from_lb" {
  security_group_id            = var.target_security_group_id
  referenced_security_group_id = aws_security_group.lb.id
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port
  description                  = "Router endpoint load balancer of ${var.cell}"
}

resource "aws_lb" "this" {
  # checkov:skip=CKV_AWS_91: access logs of an NLB cover TLS listeners only; this one is TCP inside the VPC, flow logs cover it
  name                             = substr(local.name, 0, 32)
  internal                         = true
  load_balancer_type               = "network"
  subnets                          = var.subnet_ids
  security_groups                  = [aws_security_group.lb.id]
  enable_cross_zone_load_balancing = true
  enable_deletion_protection       = var.environment != "dev"
  tags                             = var.tags
}

resource "aws_lb_target_group" "this" {
  name                 = substr("${var.name_prefix}-${var.environment}-${var.region_short}-${var.cell}-rtr", 0, 32)
  port                 = var.port
  protocol             = "TCP"
  target_type          = "ip"
  vpc_id               = var.vpc_id
  deregistration_delay = 60

  health_check {
    protocol            = "TCP"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
  }

  tags = var.tags
}

resource "aws_lb_listener" "this" {
  load_balancer_arn = aws_lb.this.arn
  port              = var.port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  tags = var.tags
}

resource "aws_route53_record" "this" {
  zone_id = aws_route53_zone.this.zone_id
  name    = local.host
  type    = "A"

  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = true
  }
}

# The controller of the cell cluster only registers gateway pod IPs in this target group; security groups stay with Terraform.
resource "aws_iam_role" "controller" {
  name                 = "${local.name}-controller"
  permissions_boundary = var.permissions_boundary_arn
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Condition = {
        StringEquals = { "aws:SourceAccount" = var.account_id }
        ArnEquals    = { "aws:SourceArn" = var.cell_cluster_arn }
      }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "controller" {
  name = "target-group-binding"
  role = aws_iam_role.controller.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "RegisterGatewayPods", Effect = "Allow", Action = ["elasticloadbalancing:RegisterTargets", "elasticloadbalancing:DeregisterTargets"], Resource = [aws_lb_target_group.this.arn] },
      # Describe calls have no resource-level scoping.
      {
        Sid      = "Describe"
        Effect   = "Allow"
        Action   = ["elasticloadbalancing:DescribeTargetGroups", "elasticloadbalancing:DescribeTargetHealth", "elasticloadbalancing:DescribeLoadBalancers", "elasticloadbalancing:DescribeListeners", "elasticloadbalancing:DescribeTags", "ec2:DescribeInstances", "ec2:DescribeNetworkInterfaces", "ec2:DescribeSubnets", "ec2:DescribeSecurityGroups", "ec2:DescribeVpcs"]
        Resource = "*"
      },
    ]
  })
}

resource "aws_eks_pod_identity_association" "controller" {
  cluster_name    = var.cell_cluster_name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.controller.arn
  tags            = var.tags
}
