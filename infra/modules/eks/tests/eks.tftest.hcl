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
}

variables {
  name_prefix              = "pay"
  region                   = "eu-central-1"
  environment              = "dev"
  component                = "eks-cell-0"
  kubernetes_version       = "1.34"
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

run "locker_pod_group_is_separate_from_the_node_group" {
  command = plan

  assert {
    condition     = aws_security_group.locker_pod.name != aws_security_group.node.name && aws_vpc_security_group_egress_rule.locker_pod_vpc.cidr_ipv4 == var.vpc_cidr_block
    error_message = "the locker pod group is its own group with VPC-only egress"
  }
}
