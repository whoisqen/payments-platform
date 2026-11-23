# Individual values (accounts, networks, domains, contacts) come from config/platform.yaml; only sizing lives here.
locals {
  cfg = yamldecode(file("${get_repo_root()}/config/platform.yaml"))

  environment                = "stage"
  account_id                 = local.cfg.accounts.stage
  shared_services_account_id = local.cfg.accounts.shared_services
  owner                      = local.cfg.owner.contact_email
  cost_center                = "${local.cfg.owner.cost_center_prefix}-stage"

  state_kms_key_arn        = local.cfg.storage.state_kms_key_arn
  permissions_boundary_arn = "arn:aws:iam::${local.account_id}:policy/workload-boundary"
  flow_logs_bucket_arn     = "arn:aws:s3:::${local.cfg.storage.state_bucket_prefix}-stage-log-archive-flow-logs"
  autoscaling_slr_arn      = "arn:aws:iam::${local.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"

  kubernetes_version   = "1.34"
  bottlerocket_version = "v1.49.0"

  azs = {
    "eu-central-1" = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
    "us-east-1"    = ["us-east-1a", "us-east-1b", "us-east-1c"]
    "us-east-2"    = ["us-east-2a", "us-east-2b", "us-east-2c"]
  }

  vpc_cidrs   = { for region, cidr in local.cfg.network.stage : region => cidr if !startswith(region, "egress") }
  egress_cidr = local.cfg.network.stage.egress
  # Each region with workloads has its own egress VPC and transit gateway (no cross-region path for PSP traffic).
  egress_cidrs = { for r in concat([local.cfg.regions.working], slice(local.cfg.regions.recovery, 0, 1)) : r => r == local.cfg.regions.working ? local.cfg.network.stage.egress : local.cfg.network.stage["egress-${r}"] }

  # Set after the first apply of tgw: the vpc stack needs the attachment before it may route through it (two-step by design).
  # Region => transit gateway id, filled in config/platform.yaml (deploy.stage.transit_gateway_ids) after tgw is applied.
  transit_gateway_ids = try(local.cfg.deploy.stage.transit_gateway_ids, {})

  psp_domains = local.cfg.dns.psp_domains
  zone_name   = local.cfg.dns.stage_zone

  cells = ["cell-0", "cell-1", "cell-2", "cell-3", "spare"]
  kms_keys = merge(
    {
      "ebs-nodes" = { user_role_arns = [local.autoscaling_slr_arn] }
      "logs"      = { service_principals = ["logs.amazonaws.com"] }
      "shared"    = {}
      "locker"    = {}
      "backup"    = {}
    },
    { for c in ["cell-0", "cell-1", "cell-2", "cell-3", "spare"] : c => {} },
  )

  memorydb_users = {
    router    = "on ~* &* +@all -@admin -@dangerous"
    drainer   = "on ~* &* +@all -@admin -@dangerous"
    scheduler = "on ~* &* +@all -@admin -@dangerous"
  }

  # People get view only; ArgoCD is limited to the platform namespaces and never cluster-admin.
  access_entries = {
    sre-view = {
      principal_arn = "arn:aws:iam::${local.account_id}:role/aws-reserved/sso.amazonaws.com/${local.cfg.access.sre_view_permission_set}"
      policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
    }
    argocd = {
      principal_arn = "arn:aws:iam::${local.account_id}:role/${local.cfg.storage.state_bucket_prefix}-stage-argocd-controller"
      policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminPolicy"
      scope         = "namespace"
      namespaces    = ["router", "locker", "drainer", "scheduler", "external-secrets", "karpenter", "istio-system", "kyverno"]
    }
  }

  # Sizing comes from config/environments: prod.yaml is the reference, <env>.yaml overrides it one level deep.
  sizing_reference = yamldecode(file("${get_repo_root()}/config/environments/prod.yaml"))
  sizing_own       = yamldecode(file("${get_repo_root()}/config/environments/stage.yaml"))
  sizing           = { for k, v in local.sizing_reference : k => merge(v, lookup(local.sizing_own, k, {})) }

  eks_log_retention_days = local.sizing.eks.log_retention_days
  karpenter_cpu_limits   = local.sizing.eks.cpu_limits
  karpenter_spot_pools   = local.sizing.eks.spot_pools

  aurora_writer_class  = local.sizing.aurora.writer_class
  aurora_reader_class  = local.sizing.aurora.reader_class
  aurora_reader_count  = local.sizing.aurora.reader_count
  memorydb_node_type   = local.sizing.memorydb.node_type
  memorydb_shards      = local.sizing.memorydb.shards
  deletion_protection  = local.sizing.protection.deletion_protection
  vault_lock_enabled   = local.sizing.protection.vault_lock_enabled
  standby_enabled      = local.sizing.standby.enabled
  standby_reader_count = local.sizing.standby.reader_count
  standby_reader_class = local.sizing.standby.reader_class
  standby_node_pool    = local.sizing.standby.node_pool_cpu_limits
  ingress_endpoints     = local.cfg.deploy.stage.ingress_endpoints
}
