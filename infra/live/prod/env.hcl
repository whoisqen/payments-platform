# Individual values (accounts, networks, domains, contacts) come from config/platform.yaml; only sizing lives here.
locals {
  cfg = yamldecode(file("${get_repo_root()}/config/platform.yaml"))

  environment                = "prod"
  account_id                 = local.cfg.accounts.prod
  shared_services_account_id = local.cfg.accounts.shared_services
  owner                      = local.cfg.owner.contact_email
  cost_center                = "${local.cfg.owner.cost_center_prefix}-prod"

  state_kms_key_arn        = local.cfg.storage.state_kms_key_arn
  permissions_boundary_arn = "arn:aws:iam::${local.account_id}:policy/workload-boundary"
  # Region switch role from ci-oidc-roles (vars.AWS_ROLE_DR_APPLY); the standby Argo CD install uses it as the installer.
  dr_apply_role_arn    = "arn:aws:iam::${local.account_id}:role/${local.cfg.naming.prefix}-prod-glob-dr-apply"
  flow_logs_bucket_arn = "arn:aws:s3:::${local.cfg.storage.state_bucket_prefix}-prod-log-archive-flow-logs"
  autoscaling_slr_arn  = "arn:aws:iam::${local.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"

  kubernetes_version   = "1.36"
  bottlerocket_version = "v1.70.0"

  azs = {
    "eu-central-1" = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
    "us-east-1"    = ["us-east-1a", "us-east-1b", "us-east-1c"]
  }

  vpc_cidrs   = { for region, cidr in local.cfg.network.prod : region => cidr if !startswith(region, "egress") }
  egress_cidr = local.cfg.network.prod.egress
  # Each region with workloads has its own egress VPC and transit gateway (no cross-region path for PSP traffic).
  egress_cidrs = { for r in concat([local.cfg.regions.working], slice(local.cfg.regions.recovery, 0, 1)) : r => r == local.cfg.regions.working ? local.cfg.network.prod.egress : local.cfg.network.prod["egress-${r}"] }

  # Set after the first apply of tgw: the vpc stack needs the attachment before it may route through it (two-step by design).
  # Region => transit gateway id, filled in config/platform.yaml (deploy.prod.transit_gateway_ids) after tgw is applied.
  transit_gateway_ids = try(local.cfg.deploy.prod.transit_gateway_ids, {})

  psp_domains = local.cfg.dns.psp_domains
  zone_name   = local.cfg.dns.prod_zone

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
      principal_arn = "arn:aws:iam::${local.account_id}:role/${local.cfg.storage.state_bucket_prefix}-prod-argocd-controller"
      policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminPolicy"
      scope         = "namespace"
      namespaces    = ["router", "locker", "drainer", "scheduler", "external-secrets", "karpenter", "istio-system", "kyverno"]
    }
  }

  # Sizing comes from config/environments: prod.yaml is the reference, <env>.yaml overrides it one level deep.
  sizing_reference = yamldecode(file("${get_repo_root()}/config/environments/prod.yaml"))
  sizing_own       = yamldecode(file("${get_repo_root()}/config/environments/prod.yaml"))
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
  # Hot standby: us-east-1 runs all the time at the working size; config may switch it off only as a fallback, PAY_STANDBY_COMPUTE forces it on.
  standby_compute_enabled = try(local.sizing.standby.compute_enabled, true) || get_env("PAY_STANDBY_COMPUTE", "false") == "true"
  standby_enabled         = try(local.sizing.standby.enabled, true) && local.standby_compute_enabled
  # One us-east-1 instance per Aurora cluster; each unit gives it the writer class of its working cluster.
  standby_reader_count = try(local.sizing.standby.reader_count, 1)
  ingress_endpoints    = local.cfg.deploy.prod.ingress_endpoints

  # Analytics outside the CDE: MSK, OpenSearch and ClickHouse on its own cluster. config/environments may set msk, opensearch and
  # analytics_eks (prod.yaml is the reference, so dev.yaml must lower them); until then these defaults hold, sized to the measured load:
  # about 4 TB of events a month, 7 days at replication factor 3 is about 2.8 TB of broker storage.
  analytics = {
    msk = {
      broker_count        = try(local.sizing.msk.broker_count, 3)
      instance_type       = try(local.sizing.msk.instance_type, "kafka.m7g.large")
      volume_size_gb      = try(local.sizing.msk.volume_size_gb, 1000)
      enhanced_monitoring = try(local.sizing.msk.enhanced_monitoring, "PER_TOPIC_PER_PARTITION")
    }
    opensearch = {
      availability_zone_count = try(local.sizing.opensearch.availability_zone_count, 3)
      data_node_count         = try(local.sizing.opensearch.data_node_count, 3)
      data_instance_type      = try(local.sizing.opensearch.data_instance_type, "r7g.xlarge.search")
      dedicated_master_count  = try(local.sizing.opensearch.dedicated_master_count, 3)
      warm_node_count         = try(local.sizing.opensearch.warm_node_count, 2)
      volume_size_gb          = try(local.sizing.opensearch.volume_size_gb, 1024)
    }
    # ClickHouse (2 shards x 2 replicas on r7g.2xlarge plus 3 Keeper nodes) runs in the stateful pool; Spot only where the cells allow it.
    cpu_limits = try(local.sizing.analytics_eks.cpu_limits, { stateful = 48, workers = 32 })
    spot_pools = [for p in local.karpenter_spot_pools : p if contains(["stateful", "workers"], p)]
  }

  # Argo CD of the analytics cluster reaches only its own namespaces.
  analytics_access_entries = merge(local.access_entries, {
    argocd = merge(local.access_entries.argocd, { namespaces = ["clickhouse", "monitoring", "karpenter", "external-secrets"] })
  })
}
