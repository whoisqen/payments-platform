mock_provider "aws" {
  mock_resource "aws_eks_cluster" {
    defaults = {
      arn      = "arn:aws:eks:eu-central-1:111111111111:cluster/pay-dev-euc1-eks-cell-0"
      endpoint = "https://ABC.gr7.eu-central-1.eks.amazonaws.com"
      identity = [{ oidc = [{ issuer = "https://oidc.eks.eu-central-1.amazonaws.com/id/ABC" }] }]
      vpc_config = [{
        cluster_security_group_id = "sg-0cluster"
        subnet_ids                = []
        security_group_ids        = []
      }]
    }
  }
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::111111111111:role/mock"
    }
  }
  mock_resource "aws_kinesis_firehose_delivery_stream" {
    defaults = {
      arn = "arn:aws:firehose:eu-central-1:111111111111:deliverystream/mock"
    }
  }
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111111111111"
    }
  }
  mock_data "aws_eks_addon_version" {
    defaults = {
      version = "v1.0.0-eksbuild.1"
    }
  }
}

variables {
  name_prefix              = "pay"
  region                   = "eu-central-1"
  environment              = "dev"
  component                = "eks-cell-0"
  kubernetes_version       = "1.37"
  vpc_id                   = "vpc-0abc"
  vpc_cidr_block           = "10.104.0.0/16"
  subnet_ids               = ["subnet-a", "subnet-b", "subnet-c"]
  secrets_kms_key_arn      = "arn:aws:kms:eu-central-1:111111111111:key/aaaa"
  logs_kms_key_arn         = "arn:aws:kms:eu-central-1:111111111111:key/bbbb"
  ebs_kms_key_arn          = "arn:aws:kms:eu-central-1:111111111111:key/cccc"
  permissions_boundary_arn = "arn:aws:iam::111111111111:policy/workload-boundary"
  tags = {
    team = "platform", owner = "platform@example.com", pci-scope = "cde", data-class = "card-data", backup-tier = "none"
  }
}

run "endpoint_is_private_and_secrets_are_encrypted" {
  command = plan

  assert {
    condition     = aws_eks_cluster.this.vpc_config[0].endpoint_private_access && !aws_eks_cluster.this.vpc_config[0].endpoint_public_access
    error_message = "the endpoint must be private only"
  }
  assert {
    condition     = aws_eks_cluster.this.encryption_config[0].provider[0].key_arn == var.secrets_kms_key_arn && aws_eks_cluster.this.encryption_config[0].resources == toset(["secrets"])
    error_message = "secrets must be encrypted with the customer managed key"
  }
  assert {
    condition     = aws_eks_cluster.this.access_config[0].authentication_mode == "API" && !aws_eks_cluster.this.access_config[0].bootstrap_cluster_creator_admin_permissions
    error_message = "access entries only, no creator admin"
  }
  assert {
    condition     = aws_eks_cluster.this.name == "pay-dev-euc1-eks-cell-0"
    error_message = "cluster name follows pay-<env>-<region-short>-<component>"
  }
}

run "all_control_plane_logs_go_to_an_encrypted_group" {
  command = plan

  assert {
    condition     = length(aws_eks_cluster.this.enabled_cluster_log_types) == 5
    error_message = "all five log types must be enabled"
  }
  assert {
    condition     = aws_cloudwatch_log_group.cluster.kms_key_id == var.logs_kms_key_arn && aws_cloudwatch_log_group.cluster.retention_in_days == 365
    error_message = "the log group is encrypted and kept one year"
  }
}

run "bootstrap_nodes_are_hardened" {
  command = plan

  assert {
    condition     = aws_launch_template.bootstrap.metadata_options[0].http_tokens == "required" && aws_launch_template.bootstrap.metadata_options[0].http_put_response_hop_limit == 1
    error_message = "IMDSv2 with hop limit 1"
  }
  assert {
    condition     = alltrue([for b in aws_launch_template.bootstrap.block_device_mappings : b.ebs[0].encrypted && b.ebs[0].volume_type == "gp3" && b.ebs[0].kms_key_id == var.ebs_kms_key_arn])
    error_message = "volumes are encrypted gp3 with the nodes key"
  }
  assert {
    condition     = aws_eks_node_group.bootstrap.capacity_type == "ON_DEMAND" && aws_eks_node_group.bootstrap.ami_type == "BOTTLEROCKET_ARM_64"
    error_message = "bootstrap nodes are On-Demand Bottlerocket"
  }
}

run "addons_are_managed" {
  command = plan

  assert {
    condition     = length(setunion(keys(aws_eks_addon.before_compute), keys(aws_eks_addon.after_compute))) == 5
    error_message = "five managed add-ons"
  }
  assert {
    condition     = jsondecode(aws_eks_addon.before_compute["vpc-cni"].configuration_values).env.ENABLE_PREFIX_DELEGATION == "true"
    error_message = "vpc-cni uses prefix delegation"
  }
}

run "cluster_admin_is_rejected" {
  command = plan

  variables {
    access_entries = {
      sre = { principal_arn = "arn:aws:iam::111111111111:role/sre", policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy" }
    }
  }

  expect_failures = [var.access_entries]
}

run "view_access_entry_is_created" {
  command = plan

  variables {
    access_entries = {
      sre = { principal_arn = "arn:aws:iam::111111111111:role/sre", policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy" }
    }
  }

  assert {
    condition     = aws_eks_access_policy_association.this["sre"].access_scope[0].type == "cluster"
    error_message = "the view entry is associated"
  }
}

run "deletion_protection_is_on_outside_dev" {
  command = plan

  variables {
    environment = "stage"
  }

  assert {
    condition     = aws_eks_cluster.this.deletion_protection
    error_message = "stage clusters must be protected from deletion"
  }
}

run "deletion_protection_is_off_in_dev" {
  command = plan

  assert {
    condition     = !aws_eks_cluster.this.deletion_protection
    error_message = "dev clusters may be deleted"
  }
}

run "log_retention_follows_the_input" {
  command = plan

  variables {
    log_retention_days = 30
  }

  assert {
    condition     = aws_cloudwatch_log_group.cluster.retention_in_days == 30
    error_message = "log_retention_days must reach the log group"
  }
}

run "locker_pod_egress_defaults_to_the_vpc" {
  command = plan

  assert {
    condition     = aws_security_group.locker_pod.name != aws_security_group.node.name
    error_message = "the locker pod group is its own group"
  }

  assert {
    condition = (
      length(aws_vpc_security_group_egress_rule.locker_pod) == 5 &&
      alltrue([for r in aws_vpc_security_group_egress_rule.locker_pod : r.cidr_ipv4 == var.vpc_cidr_block && r.from_port == r.to_port]) &&
      toset([for r in aws_vpc_security_group_egress_rule.locker_pod : "${r.ip_protocol}/${r.from_port}"]) == toset(["tcp/443", "tcp/5432", "udp/53", "tcp/53", "tcp/15012"])
    )
    error_message = "without inputs the locker pods reach only 443, 5432, DNS and istiod inside the VPC"
  }
}

run "locker_pod_egress_uses_subnets_and_endpoint_group" {
  command = plan

  variables {
    locker_pod_endpoint_cidrs             = ["10.104.0.0/19"]
    locker_pod_database_cidrs             = ["10.104.96.0/24", "10.104.97.0/24", "10.104.98.0/24"]
    locker_pod_endpoint_security_group_id = "sg-0endpoints"
  }

  assert {
    condition = (
      length(aws_vpc_security_group_egress_rule.locker_pod) == 7 &&
      length([for r in aws_vpc_security_group_egress_rule.locker_pod : r if r.from_port == 443]) == 1 &&
      aws_vpc_security_group_egress_rule.locker_pod["https-endpoints"].referenced_security_group_id == "sg-0endpoints" &&
      aws_vpc_security_group_egress_rule.locker_pod["https-endpoints"].cidr_ipv4 == null
    )
    error_message = "the endpoint group replaces the 443 CIDR rules"
  }

  assert {
    condition = (
      toset([for r in aws_vpc_security_group_egress_rule.locker_pod : r.cidr_ipv4 if r.from_port == 5432]) == toset(var.locker_pod_database_cidrs) &&
      alltrue([for r in aws_vpc_security_group_egress_rule.locker_pod : r.ip_protocol == "tcp" && r.to_port == 5432 if r.from_port == 5432])
    )
    error_message = "5432 goes to the data subnets only"
  }
}

run "locker_pod_endpoint_cidrs_without_group" {
  command = plan

  variables {
    locker_pod_endpoint_cidrs = ["10.104.0.0/19", "10.104.32.0/19", "10.104.64.0/19"]
  }

  assert {
    condition     = length(aws_vpc_security_group_egress_rule.locker_pod) == 7 && toset([for r in aws_vpc_security_group_egress_rule.locker_pod : r.cidr_ipv4 if r.from_port == 443]) == toset(var.locker_pod_endpoint_cidrs)
    error_message = "443 goes to each endpoint CIDR when no endpoint group is set"
  }
}

run "locker_pod_cidrs_are_validated" {
  command = plan

  variables {
    locker_pod_database_cidrs = ["0.0.0.0/33"]
  }

  expect_failures = [var.locker_pod_database_cidrs]
}

run "unpinned_addons_follow_the_cluster_version" {
  command = plan

  variables {
    addon_versions = { coredns = "v1.13.1-eksbuild.1" }
  }

  assert {
    condition     = aws_eks_addon.after_compute["coredns"].addon_version == "v1.13.1-eksbuild.1" && aws_eks_addon.before_compute["kube-proxy"].addon_version == "v1.0.0-eksbuild.1"
    error_message = "a pinned add-on keeps its version, the others take the default of kubernetes_version"
  }
  assert {
    condition     = !contains(keys(data.aws_eks_addon_version.default), "coredns") && data.aws_eks_addon_version.default["kube-proxy"].kubernetes_version == "1.37"
    error_message = "defaults are looked up only for unpinned add-ons, for kubernetes_version"
  }
}

run "control_plane_logs_stay_in_cloudwatch_without_archive" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_log_subscription_filter.log_export) == 0 && length(aws_kinesis_firehose_delivery_stream.log_export) == 0
    error_message = "no export without log_archive"
  }
}

run "control_plane_logs_are_exported_to_the_archive" {
  command = plan

  variables {
    log_retention_days = 90
    log_archive = {
      bucket_arn = "arn:aws:s3:::pay-security-euc1-log-archive"
      account_id = "000000000002"
    }
  }

  assert {
    condition     = aws_kinesis_firehose_delivery_stream.log_export[0].extended_s3_configuration[0].bucket_arn == "arn:aws:s3:::pay-security-euc1-log-archive" && aws_kinesis_firehose_delivery_stream.log_export[0].extended_s3_configuration[0].prefix == "eks/pay-dev-euc1-eks-cell-0/"
    error_message = "the stream writes to the archive under eks/<cluster>/"
  }
  assert {
    condition     = aws_kinesis_firehose_delivery_stream.log_export[0].server_side_encryption[0].key_type == "CUSTOMER_MANAGED_CMK" && aws_kinesis_firehose_delivery_stream.log_export[0].server_side_encryption[0].key_arn == var.logs_kms_key_arn
    error_message = "the stream encrypts with the logs key"
  }
  assert {
    condition     = aws_cloudwatch_log_subscription_filter.log_export[0].log_group_name == "/aws/eks/pay-dev-euc1-eks-cell-0/cluster" && aws_cloudwatch_log_subscription_filter.log_export[0].filter_pattern == ""
    error_message = "every event of the control-plane group is subscribed"
  }
  assert {
    condition     = endswith(aws_iam_role.log_export_firehose[0].name, "-log-export") && aws_iam_role.log_export_firehose[0].permissions_boundary == var.permissions_boundary_arn
    error_message = "the writer role carries the name the archive policies admit and the boundary"
  }
  assert {
    condition     = aws_cloudwatch_log_group.cluster.retention_in_days == 90
    error_message = "with the export the group may keep 90 days"
  }
}

run "log_archive_is_validated" {
  command = plan

  variables {
    log_archive = { bucket_arn = "pay-security-euc1-log-archive", account_id = "2" }
  }

  expect_failures = [var.log_archive]
}
