locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
  prefix  = local.env_cfg.cfg.naming.prefix
  env     = local.env_cfg.environment
  short   = { "eu-central-1" = "euc1", "us-east-1" = "use1" }
  # The edge ingress load balancer of each region: the load balancer controller of the edge cluster tags it (Service annotation
  # service.beta.kubernetes.io/aws-load-balancer-additional-resource-tags: pay.io/edge-entry=true).
  edge_tags = { for r, s in local.short : r => { "elbv2.k8s.aws/cluster" = "${local.prefix}-${local.env}-${s}-eks-edge", "pay.io/edge-entry" = "true" } }
}

terraform {
  source = "${get_repo_root()}/infra/modules//global-accelerator"
}

# Global Accelerator has its control plane in us-west-2 only; this replaces the provider of the root, which follows the path region.
generate "provider_accelerator" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOT
    provider "aws" {
      region              = "us-west-2"
      allowed_account_ids = ["${local.env_cfg.account_id}"]

      assume_role {
        role_arn     = "arn:aws:iam::${local.env_cfg.account_id}:role/${local.prefix}-${local.env}-tf-exec"
        session_name = "terragrunt-${local.env}-edge-accelerator"
      }

      default_tags {
        tags = {
          environment = "${local.env}"
          cell        = "shared"
          component   = "edge-accelerator"
          cost-center = "${local.env_cfg.cost_center}"
          managed-by  = "terraform"
          repo        = "infra/live/${local.env}/eu-central-1/edge-accelerator"
        }
      }
    }
  EOT
}

inputs = {
  # Only prod has the us-east-1 standby; dev and stage serve from the working region alone.
  endpoint_groups = merge(
    { "eu-central-1" = { active = true, endpoint_lb_tags = local.edge_tags["eu-central-1"] } },
    local.env_cfg.standby_compute_enabled ? { "us-east-1" = { active = false, endpoint_lb_tags = local.edge_tags["us-east-1"] } } : {},
  )
  tags = {
    team        = "platform"
    owner       = local.env_cfg.owner
    pci-scope   = "connected"
    data-class  = "public"
    backup-tier = "none"
  }
}
