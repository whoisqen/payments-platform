# Individual values (accounts, networks, contacts) come from config/platform.yaml; only sizing lives here.
# Environment of the CI account: its tags follow the schema of policy/tagging, which still lists dev, stage and prod only.
locals {
  cfg = yamldecode(file("${get_repo_root()}/config/platform.yaml"))

  environment                = "shared-services"
  account_id                 = local.cfg.accounts.shared_services
  shared_services_account_id = local.cfg.accounts.shared_services
  owner                      = local.cfg.owner.contact_email
  cost_center                = "${local.cfg.owner.cost_center_prefix}-shared-services"

  state_kms_key_arn        = local.cfg.storage.state_kms_key_arns[local.environment]
  permissions_boundary_arn = "arn:aws:iam::${local.account_id}:policy/workload-boundary"
  flow_logs_bucket_arn     = "arn:aws:s3:::${local.cfg.storage.state_bucket_prefix}-shared-services-log-archive-flow-logs"
  autoscaling_slr_arn      = "arn:aws:iam::${local.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"

  # Trust of the runner pods and of the ci-prod push role; the plan role lives in the environment account.
  github_repository        = "${local.cfg.owner.github_org}/${local.cfg.owner.github_repo}"
  github_oidc_provider_arn = "arn:aws:iam::${local.account_id}:oidc-provider/token.actions.githubusercontent.com"
  plan_role_arn            = "arn:aws:iam::${local.cfg.accounts.stage}:role/${local.cfg.storage.state_bucket_prefix}-stage-glob-tf-plan"
  ecr_repository_arns = [
    "arn:aws:ecr:eu-central-1:${local.account_id}:repository/${local.cfg.registry.ecr_repo_prefix}/*",
  ]


  azs = {
    "eu-central-1" = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
  }

  vpc_cidrs   = { "eu-central-1" = local.cfg.network.shared_services["eu-central-1"] }
  egress_cidr = local.cfg.network.shared_services.egress

  # Set after the first apply of tgw: the vpc stack needs the attachment before it may route through it (two-step by design).
  transit_gateway_id = null

  # No PSP traffic leaves shared-services: its firewall passes only the CI allowlist of the untrusted runner tier.
  psp_domains = []

  kms_keys = {
    "ebs-nodes" = { user_role_arns = [local.autoscaling_slr_arn] }
    "logs"      = { service_principals = ["logs.amazonaws.com"] }
    "shared"    = {}
  }

  # Runner pools: one Auto Scaling group of Spot instances each, split by kind of job and never by priority.
  # warm_size instances run during working hours, min_size outside them; target_cpu is the average CPU that adds instances.
  ci_pools = {
    ci-build = { instance_types = ["c7gd.4xlarge", "c6gd.4xlarge", "m7gd.4xlarge"], min_size = 0, warm_size = 1, max_size = 8, root_volume_gb = 30, on_demand_base = 0, target_cpu = 50, labels = ["build"], cache_write = true, ecr_pull = true, assume_plan = false, untrusted = false }
    ci-test  = { instance_types = ["m7g.2xlarge", "m6g.2xlarge", "c7g.2xlarge"], min_size = 0, warm_size = 1, max_size = 16, root_volume_gb = 40, on_demand_base = 0, target_cpu = 50, labels = ["test"], cache_write = false, ecr_pull = true, assume_plan = false, untrusted = false }
    ci-light = { instance_types = ["m7g.large", "m6g.large", "c7g.large"], min_size = 0, warm_size = 1, max_size = 20, root_volume_gb = 30, on_demand_base = 0, target_cpu = 50, labels = ["light"], cache_write = false, ecr_pull = false, assume_plan = true, untrusted = false }
    ci-pr    = { instance_types = ["c7g.2xlarge", "m7g.2xlarge", "c6g.2xlarge"], min_size = 0, warm_size = 1, max_size = 20, root_volume_gb = 40, on_demand_base = 0, target_cpu = 50, labels = ["pr"], cache_write = false, ecr_pull = false, assume_plan = false, untrusted = true }
  }
  runner_version = local.cfg.runners.version
  runner_sha256  = local.cfg.runners.sha256

  # Registries pulled through the own ECR: nodes get them closer and faster, and an upstream outage does not stop CI.
  pull_through_cache = {
    "ecr-public" = { upstream_registry_url = "public.ecr.aws" }
    "k8s"        = { upstream_registry_url = "registry.k8s.io" }
    "quay"       = { upstream_registry_url = "quay.io" }
    # Logstash (opensearchproject/logstash-oss-with-opensearch-output-plugin) and kuskoman/logstash-exporter exist only on Docker Hub
    "docker-hub" = { upstream_registry_url = "registry-1.docker.io", credentials = true }
  }

  # Central observability cluster (outside the CDE): same cluster build as a cell, without the cde pool.
  kubernetes_version     = "1.36"
  bottlerocket_version   = "v1.70.0"
  eks_log_retention_days = 90
  central_cpu_limits     = { workers = 200, stateful = 200, "ci-build" = 64 }
  # ci-build: BuildKit pods of the image builds (Spot, arm64, label pay.io/pool=ci-build, taint workload=ci-build).
  central_enabled_pools = ["workers", "stateful", "ci-build"]
  # Spot only for ci-build (central_spot_pools lists none); the stateful pool (VictoriaMetrics, Tempo, Logstash, Sentry stores) stays on demand.
  central_spot_pools = []
  # Argo CD manages its own cluster in-cluster through its service accounts, so the central cluster has no argocd entry (argocd-access depends on this cluster).
  access_entries = {
    sre-view = {
      principal_arn = "arn:aws:iam::${local.account_id}:role/aws-reserved/sso.amazonaws.com/${local.cfg.access.sre_view_permission_set}"
      policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
    }
  }

  deletion_protection = true

  # Central log domain (central.opensearch). Volume from docs/architecture/cost: application logs about 30 GB a day (the 900 GB-month
  # of 30-day log storage), audit about 30 GB a day (EKS control plane 870 GB a month over prod, stage and dev, plus 50 GB of CloudTrail).
  # Hot with one replica: app 30 x 7 x 2 = 420 GB, audit 30 x 30 x 2 = 1,800 GB; with 25% free for the disk watermarks, 3,000 GB on 6 x 600 GB.
  # UltraWarm (no replica): app 30 x 23 = 690 GB, audit 30 x 335 = 10 TB; 8 x ultrawarm1.medium hold 12 TiB.
  logs_domain = {
    data_instance_type = "r7g.xlarge.search"
    data_node_count    = 6
    volume_size_gb     = 600
    warm_instance_type = "ultrawarm1.medium.search"
    warm_node_count    = 8
    log_retention_days = 90
  }
}
