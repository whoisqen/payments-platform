# Individual values (accounts, networks, domains, contacts) come from config/platform.yaml; only sizing lives here.
locals {
  cfg = yamldecode(file("${get_repo_root()}/config/platform.yaml"))

  environment                = "dev"
  account_id                 = local.cfg.accounts.dev
  shared_services_account_id = local.cfg.accounts.shared_services
  owner                      = local.cfg.owner.contact_email
  cost_center                = "${local.cfg.owner.cost_center_prefix}-dev"

  state_kms_key_arn        = local.cfg.storage.state_kms_key_arn
  permissions_boundary_arn = "arn:aws:iam::${local.account_id}:policy/workload-boundary"
  flow_logs_bucket_arn     = "arn:aws:s3:::${local.cfg.storage.state_bucket_prefix}-dev-log-archive-flow-logs"
  autoscaling_slr_arn      = "arn:aws:iam::${local.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"

  kubernetes_version   = "1.36"
  bottlerocket_version = "v1.70.0"

  azs = {
    "eu-central-1" = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
    "us-east-1"    = ["us-east-1a", "us-east-1b", "us-east-1c"]
  }

  vpc_cidrs   = { for region, cidr in local.cfg.network.dev : region => cidr if region != "egress" }
  egress_cidr = local.cfg.network.dev.egress

  # Set after the first apply of tgw: the vpc stack needs the attachment before it may route through it (two-step by design).
  transit_gateway_id = null

  psp_domains = local.cfg.dns.psp_domains
  zone_name   = local.cfg.dns.dev_zone

  # One working cell plus the spare; us-east-1 keeps only the edge (panel-edge, waf-edge and their key replicas). Multi-cell routing is tested in stage.
  cells = ["cell-0", "spare"]
  kms_keys = merge(
    {
      "ebs-nodes" = { user_role_arns = [local.autoscaling_slr_arn] }
      "logs"      = { service_principals = ["logs.amazonaws.com"] }
      "shared"    = {}
      "locker"    = {}
      "backup"    = {}
    },
    { for c in local.cells : c => {} },
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
      principal_arn = "arn:aws:iam::${local.account_id}:role/${local.cfg.storage.state_bucket_prefix}-dev-argocd-controller"
      policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminPolicy"
      scope         = "namespace"
      namespaces    = ["router", "locker", "drainer", "scheduler", "external-secrets", "karpenter", "istio-system", "kyverno"]
    }
  }

  # Sizing comes from config/environments: prod.yaml is the reference, <env>.yaml overrides it one level deep.
  sizing_reference = yamldecode(file("${get_repo_root()}/config/environments/prod.yaml"))
  sizing_own       = yamldecode(file("${get_repo_root()}/config/environments/dev.yaml"))
  sizing           = { for k, v in local.sizing_reference : k => merge(v, lookup(local.sizing_own, k, {})) }

  eks_log_retention_days = local.sizing.eks.log_retention_days
  karpenter_cpu_limits   = local.sizing.eks.cpu_limits
  karpenter_spot_pools   = local.sizing.eks.spot_pools

  aurora_writer_class = local.sizing.aurora.writer_class
  aurora_reader_class = local.sizing.aurora.reader_class
  aurora_reader_count = local.sizing.aurora.reader_count
  memorydb_node_type  = local.sizing.memorydb.node_type
  memorydb_shards     = local.sizing.memorydb.shards
  deletion_protection = local.sizing.protection.deletion_protection
  vault_lock_enabled  = local.sizing.protection.vault_lock_enabled
  # Only prod has a standby region.
  standby_compute_enabled = false
  standby_enabled         = false

  # Analytics outside the CDE: MSK, OpenSearch and ClickHouse on its own cluster. config/environments may set msk, opensearch and
  # analytics_eks (prod.yaml is the reference, so dev.yaml must lower them); until then these defaults hold, the lowest sizes (one OpenSearch node, three small brokers).
  analytics = {
    msk = {
      broker_count        = try(local.sizing.msk.broker_count, 3)
      instance_type       = try(local.sizing.msk.instance_type, "kafka.m7g.large")
      volume_size_gb      = try(local.sizing.msk.volume_size_gb, 100)
      enhanced_monitoring = try(local.sizing.msk.enhanced_monitoring, "DEFAULT")
    }
    opensearch = {
      availability_zone_count = try(local.sizing.opensearch.availability_zone_count, 1)
      data_node_count         = try(local.sizing.opensearch.data_node_count, 1)
      data_instance_type      = try(local.sizing.opensearch.data_instance_type, "m7g.medium.search")
      dedicated_master_count  = try(local.sizing.opensearch.dedicated_master_count, 0)
      warm_node_count         = try(local.sizing.opensearch.warm_node_count, 0)
      volume_size_gb          = try(local.sizing.opensearch.volume_size_gb, 20)
    }
    # ClickHouse (1 shard, 1 replica) runs in the stateful pool; Spot only where the cells allow it.
    cpu_limits = try(local.sizing.analytics_eks.cpu_limits, { stateful = 16, workers = 8 })
    spot_pools = [for p in local.karpenter_spot_pools : p if contains(["stateful", "workers"], p)]
  }

  # Argo CD of the analytics cluster reaches only its own namespaces.
  analytics_access_entries = merge(local.access_entries, {
    argocd = merge(local.access_entries.argocd, { namespaces = ["clickhouse", "monitoring", "karpenter", "external-secrets"] })
  })
}
