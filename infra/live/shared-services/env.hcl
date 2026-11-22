# Individual values (accounts, networks, contacts) come from config/platform.yaml; only sizing lives here.
# Environment of the CI account: its tags follow the schema of policy/tagging, which still lists dev, stage and prod only.
locals {
  cfg = yamldecode(file("${get_repo_root()}/config/platform.yaml"))

  environment                = "shared-services"
  account_id                 = local.cfg.accounts.shared_services
  shared_services_account_id = local.cfg.accounts.shared_services
  owner                      = local.cfg.owner.contact_email
  cost_center                = "${local.cfg.owner.cost_center_prefix}-shared-services"

  state_kms_key_arn        = local.cfg.storage.state_kms_key_arn
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

  kubernetes_version   = "1.34"
  bottlerocket_version = "v1.49.0"

  azs = {
    "eu-central-1" = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
  }

  vpc_cidrs   = { "eu-central-1" = local.cfg.network.shared_services["eu-central-1"] }
  egress_cidr = local.cfg.network.shared_services.egress

  # Set after the first apply of tgw: the vpc stack needs the attachment before it may route through it (two-step by design).
  transit_gateway_id = null

  kms_keys = {
    "ebs-nodes"     = { user_role_arns = [local.autoscaling_slr_arn] }
    "logs"          = { service_principals = ["logs.amazonaws.com"] }
    "shared"        = {}
    "runners-cache" = {}
  }

  # People get view only; ArgoCD is limited to the ARC and ESO namespaces and never cluster-admin.
  access_entries = {
    sre-view = {
      principal_arn = "arn:aws:iam::${local.account_id}:role/aws-reserved/sso.amazonaws.com/${local.cfg.access.sre_view_permission_set}"
      policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
    }
    argocd = {
      principal_arn = "arn:aws:iam::${local.account_id}:role/${local.cfg.storage.state_bucket_prefix}-shared-services-argocd-controller"
      policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminPolicy"
      scope         = "namespace"
      namespaces    = ["arc-systems", "arc-ci-prod", "arc-ci-stage", "arc-ci-pr", "external-secrets"]
    }
  }

  eks_log_retention_days = 90
  # Runner pool CPU caps; ci-pr has its own pool so that untrusted pull requests never share nodes with ci-stage.
  karpenter_cpu_limits = {
    ci      = 32
    ci-prod = 16
    ci-pr   = 16
  }
  enabled_pools = ["ci", "ci-prod", "ci-pr"]

  deletion_protection = true
}
