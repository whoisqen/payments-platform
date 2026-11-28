locals {
  locker_pod_database_cidrs = length(var.locker_pod_database_cidrs) > 0 ? var.locker_pod_database_cidrs : [var.vpc_cidr_block]
  locker_pod_endpoint_cidrs = length(var.locker_pod_endpoint_cidrs) > 0 ? var.locker_pod_endpoint_cidrs : [var.vpc_cidr_block]

  # Strict pod security group mode: every packet of a locker pod passes this group, so DNS and istiod need their own rules.
  locker_pod_egress = merge(
    var.locker_pod_endpoint_security_group_id != null ? {
      "https-endpoints" = { cidr = null, sg = var.locker_pod_endpoint_security_group_id, protocol = "tcp", port = 443, description = "HTTPS to the VPC interface endpoints (KMS)" }
      } : {
      for c in local.locker_pod_endpoint_cidrs : "https-${c}" => { cidr = c, sg = null, protocol = "tcp", port = 443, description = "HTTPS to the VPC interface endpoints (KMS)" }
    },
    { for c in local.locker_pod_database_cidrs : "postgres-${c}" => { cidr = c, sg = null, protocol = "tcp", port = 5432, description = "PostgreSQL to the card-vault RDS Proxy" } },
    {
      "dns-udp" = { cidr = var.vpc_cidr_block, sg = null, protocol = "udp", port = 53, description = "DNS to CoreDNS" }
      "dns-tcp" = { cidr = var.vpc_cidr_block, sg = null, protocol = "tcp", port = 53, description = "DNS to CoreDNS" }
      "istiod"  = { cidr = var.vpc_cidr_block, sg = null, protocol = "tcp", port = 15012, description = "Mesh xDS and certificates from istiod" }
    },
  )

  region_short = join("", [split("-", var.region)[0], substr(split("-", var.region)[1], 0, 1), split("-", var.region)[2]])
  name         = "${var.name_prefix}-${var.environment}-${local.region_short}-${var.component}"
  argocd_name  = coalesce(var.argocd_cluster_name, "${var.name_prefix}-${var.environment}-${local.region_short}-${trimprefix(var.component, "eks-")}")

  pods_trust = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })

  # Add-ons the nodes need in order to become Ready are created before the node group, the others after it.
  before_compute = {
    "eks-pod-identity-agent" = {}
    "kube-proxy"             = {}
    "vpc-cni" = {
      role_arn        = aws_iam_role.addon["vpc-cni"].arn
      service_account = "aws-node"
      config          = jsonencode({ env = { ENABLE_PREFIX_DELEGATION = "true", WARM_PREFIX_TARGET = "1", ENABLE_POD_ENI = "true" } })
    }
  }
  after_compute = {
    "coredns" = {}
    "aws-ebs-csi-driver" = {
      role_arn        = aws_iam_role.addon["aws-ebs-csi-driver"].arn
      service_account = "ebs-csi-controller-sa"
      config          = null
    }
  }
  addon_roles = {
    "vpc-cni"            = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
    "aws-ebs-csi-driver" = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  }
}

resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${local.name}/cluster"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn
  tags              = var.tags
}

resource "aws_iam_role" "cluster" {
  name                 = "${local.name}-cluster"
  permissions_boundary = var.permissions_boundary_arn
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# The key policy delegates to the account, so the cluster role gets its key rights on the IAM side.
# Lets the VPC resource controller attach branch ENIs, which pod security groups (the locker pod group) need.
resource "aws_iam_role_policy_attachment" "cluster_vpc_resource_controller" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}

resource "aws_iam_role_policy" "cluster_secrets_key" {
  name = "secrets-encryption"
  role = aws_iam_role.cluster.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["kms:Encrypt", "kms:Decrypt", "kms:DescribeKey", "kms:ListGrants", "kms:CreateGrant"]
      Resource = [var.secrets_kms_key_arn]
    }]
  })
}

resource "aws_eks_cluster" "this" {
  name                          = local.name
  role_arn                      = aws_iam_role.cluster.arn
  version                       = var.kubernetes_version
  enabled_cluster_log_types     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  bootstrap_self_managed_addons = false
  deletion_protection           = var.environment != "dev"

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = false
  }

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = false
  }

  encryption_config {
    resources = ["secrets"]
    provider {
      key_arn = var.secrets_kms_key_arn
    }
  }

  upgrade_policy {
    support_type = "STANDARD"
  }

  tags = var.tags

  depends_on = [
    aws_cloudwatch_log_group.cluster,
    aws_iam_role_policy_attachment.cluster,
    aws_iam_role_policy.cluster_secrets_key,
  ]
}

# EKS ignores the thumbprint of its own issuer, so no TLS lookup is needed.
resource "aws_iam_openid_connect_provider" "this" {
  url            = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list = ["sts.amazonaws.com"]
  tags           = var.tags
}

resource "aws_eks_access_entry" "this" {
  for_each = var.access_entries

  cluster_name      = aws_eks_cluster.this.name
  principal_arn     = each.value.principal_arn
  kubernetes_groups = each.value.kubernetes_groups
  type              = "STANDARD"
  tags              = var.tags
}

resource "aws_eks_access_policy_association" "this" {
  for_each = var.access_entries

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_eks_access_entry.this[each.key].principal_arn
  policy_arn    = each.value.policy_arn

  access_scope {
    type       = each.value.scope
    namespaces = each.value.scope == "namespace" ? each.value.namespaces : null
  }
}

resource "aws_security_group" "node" {
  name        = "${local.name}-node"
  description = "Nodes of ${local.name}; Karpenter selects it by id."
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${local.name}-node" })
}

# Pod security group of the locker (card vault) pods, applied with a SecurityGroupPolicy in the locker namespace;
# the card-vault Aurora proxy admits this group and no other group of the cluster.
resource "aws_security_group" "locker_pod" {
  name        = "${local.name}-locker-pod"
  description = "Locker pods of ${local.name}; the only client group of the card-vault database proxy."
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${local.name}-locker-pod" })
}

resource "aws_vpc_security_group_ingress_rule" "locker_pod_from_node" {
  security_group_id            = aws_security_group.locker_pod.id
  referenced_security_group_id = aws_security_group.node.id
  ip_protocol                  = "-1"
  description                  = "Kubelet probes and mesh traffic from nodes"
}

resource "aws_vpc_security_group_ingress_rule" "node_from_locker_pod" {
  security_group_id            = aws_security_group.node.id
  referenced_security_group_id = aws_security_group.locker_pod.id
  ip_protocol                  = "-1"
  description                  = "Locker pods to CoreDNS and cluster services"
}

# Pod Identity agent traffic to 169.254.170.23 is link-local and not governed by security groups, so no rule covers it.
resource "aws_vpc_security_group_egress_rule" "locker_pod" {
  for_each = local.locker_pod_egress

  security_group_id            = aws_security_group.locker_pod.id
  cidr_ipv4                    = each.value.cidr
  referenced_security_group_id = each.value.sg
  ip_protocol                  = each.value.protocol
  from_port                    = each.value.port
  to_port                      = each.value.port
  description                  = each.value.description
}

resource "aws_vpc_security_group_ingress_rule" "node_from_cluster" {
  # checkov:skip=CKV_AWS_25: the source is the EKS cluster security group, not 0.0.0.0/0; 1025-65535 is the range AWS documents for control plane to kubelet and webhooks
  security_group_id            = aws_security_group.node.id
  referenced_security_group_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 1025
  to_port                      = 65535
  description                  = "Control plane to kubelet and webhooks"
}

resource "aws_vpc_security_group_ingress_rule" "node_from_node" {
  security_group_id            = aws_security_group.node.id
  referenced_security_group_id = aws_security_group.node.id
  ip_protocol                  = "-1"
  description                  = "Pod traffic between nodes"
}

resource "aws_vpc_security_group_ingress_rule" "cluster_from_node" {
  security_group_id            = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  referenced_security_group_id = aws_security_group.node.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  description                  = "Nodes to the private endpoint"
}

resource "aws_vpc_security_group_ingress_rule" "cluster_from_central" {
  for_each = toset(var.api_ingress_cidrs)

  security_group_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  cidr_ipv4         = each.key
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "Central cluster (Argo CD, Vault) to the private endpoint"
}

resource "aws_vpc_security_group_egress_rule" "node_central" {
  for_each = { for pair in setproduct(var.central_egress.cidrs, var.central_egress.ports) : "${pair[0]}/${pair[1]}" => { cidr = pair[0], port = pair[1] } }

  security_group_id = aws_security_group.node.id
  cidr_ipv4         = each.value.cidr
  ip_protocol       = "tcp"
  from_port         = each.value.port
  to_port           = each.value.port
  description       = "Telemetry to shared-services"
}

resource "aws_vpc_security_group_egress_rule" "node_vpc" {
  security_group_id = aws_security_group.node.id
  cidr_ipv4         = var.vpc_cidr_block
  ip_protocol       = "-1"
  description       = "Inside the VPC"
}

# PSP traffic leaves through the transit gateway default route, where Network Firewall filters it by domain.
resource "aws_vpc_security_group_egress_rule" "node_https" {
  security_group_id = aws_security_group.node.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "HTTPS to PSPs, filtered by Network Firewall"
}

resource "aws_iam_role" "bootstrap_node" {
  name                 = "${local.name}-bootstrap"
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

resource "aws_iam_role_policy_attachment" "bootstrap_node" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ])

  role       = aws_iam_role.bootstrap_node.name
  policy_arn = each.value
}

resource "aws_launch_template" "bootstrap" {
  name_prefix = "${local.name}-bootstrap-"

  # The node group references the template by id and version, so a replacement needs the new one to exist first.
  lifecycle {
    create_before_destroy = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 4
      volume_type = "gp3"
      encrypted   = true
      kms_key_id  = var.ebs_kms_key_arn
    }
  }

  block_device_mappings {
    device_name = "/dev/xvdb"
    ebs {
      volume_size = 80
      volume_type = "gp3"
      encrypted   = true
      kms_key_id  = var.ebs_kms_key_arn
    }
  }

  vpc_security_group_ids = [aws_security_group.node.id, aws_eks_cluster.this.vpc_config[0].cluster_security_group_id]

  # Same container log rotation as the Karpenter node class; EKS merges its own [settings.kubernetes] keys with these.
  user_data = base64encode(<<-EOT
    [settings.kernel]
    lockdown = "integrity"
    [settings.kubernetes]
    container-log-max-size = "${var.container_log_max_size}"
    container-log-max-files = ${var.container_log_max_files}
    [settings.host-containers.admin]
    enabled = false
  EOT
  )

  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.tags, { Name = "${local.name}-bootstrap" })
  }
  tag_specifications {
    resource_type = "volume"
    tags          = var.tags
  }
}

# An unpinned add-on follows the default version of the cluster version, so a control-plane upgrade moves it too.
data "aws_eks_addon_version" "default" {
  for_each = setsubtract(setunion(keys(local.before_compute), keys(local.after_compute)), keys(var.addon_versions))

  addon_name         = each.key
  kubernetes_version = var.kubernetes_version
}

resource "aws_eks_addon" "before_compute" {
  for_each = local.before_compute

  cluster_name         = aws_eks_cluster.this.name
  addon_name           = each.key
  addon_version        = try(var.addon_versions[each.key], data.aws_eks_addon_version.default[each.key].version)
  configuration_values = try(each.value.config, null)
  tags                 = var.tags

  dynamic "pod_identity_association" {
    for_each = try(each.value.role_arn, null) == null ? [] : [each.value]
    content {
      role_arn        = pod_identity_association.value.role_arn
      service_account = pod_identity_association.value.service_account
    }
  }
}

resource "aws_eks_node_group" "bootstrap" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "bootstrap"
  node_role_arn   = aws_iam_role.bootstrap_node.arn
  subnet_ids      = var.subnet_ids
  # Follows the control plane; without it the group keeps the version it was created with.
  version        = aws_eks_cluster.this.version
  ami_type       = "BOTTLEROCKET_ARM_64"
  capacity_type  = "ON_DEMAND"
  instance_types = var.bootstrap_instance_types
  tags           = var.tags

  launch_template {
    id      = aws_launch_template.bootstrap.id
    version = aws_launch_template.bootstrap.latest_version
  }

  scaling_config {
    desired_size = var.bootstrap_node_count
    min_size     = var.bootstrap_node_count
    max_size     = var.bootstrap_node_count + 3
  }

  taint {
    key    = "CriticalAddonsOnly"
    value  = "true"
    effect = "NO_SCHEDULE"
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [aws_iam_role_policy_attachment.bootstrap_node, aws_eks_addon.before_compute]

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

resource "aws_iam_role" "addon" {
  for_each = local.addon_roles

  name                 = "${local.name}-${each.key}"
  permissions_boundary = var.permissions_boundary_arn
  assume_role_policy   = local.pods_trust
  tags                 = var.tags
}

resource "aws_iam_role_policy_attachment" "addon" {
  for_each = local.addon_roles

  role       = aws_iam_role.addon[each.key].name
  policy_arn = each.value
}

resource "aws_iam_role_policy" "ebs_csi_key" {
  name = "ebs-key"
  role = aws_iam_role.addon["aws-ebs-csi-driver"].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["kms:CreateGrant", "kms:Decrypt", "kms:DescribeKey", "kms:GenerateDataKeyWithoutPlaintext", "kms:ReEncrypt*"]
      Resource = [var.ebs_kms_key_arn]
    }]
  })
}

resource "aws_eks_addon" "after_compute" {
  for_each = local.after_compute

  cluster_name         = aws_eks_cluster.this.name
  addon_name           = each.key
  addon_version        = try(var.addon_versions[each.key], data.aws_eks_addon_version.default[each.key].version)
  configuration_values = try(each.value.config, null)
  tags                 = var.tags

  dynamic "pod_identity_association" {
    for_each = try(each.value.role_arn, null) == null ? [] : [each.value]
    content {
      role_arn        = pod_identity_association.value.role_arn
      service_account = pod_identity_association.value.service_account
    }
  }

  depends_on = [aws_eks_node_group.bootstrap]
}

