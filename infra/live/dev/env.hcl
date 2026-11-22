# Placeholders: account IDs, CIDRs, ARNs and domains below are replaced by the real values after the AFT accounts and IPAM exist.
locals {
  environment                = "dev"
  account_id                 = "111111111111"
  shared_services_account_id = "222222222222"
  owner                      = "platform@example.com"
  cost_center                = "cc-dev"

  # Output state_kms_key_arn of infra/bootstrap.
  state_kms_key_arn        = "arn:aws:kms:eu-central-1:222222222222:key/mrk-00000000000000000000000000000000"
  permissions_boundary_arn = "arn:aws:iam::111111111111:policy/workload-boundary"
  flow_logs_bucket_arn     = "arn:aws:s3:::pay-dev-log-archive-flow-logs"
  autoscaling_slr_arn      = "arn:aws:iam::111111111111:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"

  kubernetes_version   = "1.34"
  bottlerocket_version = "v1.49.0"

  azs = {
    "eu-central-1" = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
    "us-east-1"    = ["us-east-1a", "us-east-1b", "us-east-1c"]
    "us-east-2"    = ["us-east-2a", "us-east-2b", "us-east-2c"]
  }

  vpc_cidrs = {
    "eu-central-1" = "10.120.0.0/16"
    "us-east-1"    = "10.121.0.0/16"
    "us-east-2"    = "10.122.0.0/16"
  }
  egress_cidr = "10.123.0.0/20"

  # Set after the first apply of tgw: the vpc stack needs the attachment before it may route through it (two-step by design).
  transit_gateway_id = null

  psp_domains = [".psp-sandbox.example.com"]
  zone_name   = "dev.pay.example.com"

  cells = ["cell-0", "cell-1", "cell-2", "cell-3", "spare"]
  kms_keys = merge(
    {
      "ebs-nodes" = { user_role_arns = ["arn:aws:iam::111111111111:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"] }
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
      principal_arn = "arn:aws:iam::111111111111:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_SRE-View"
      policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
    }
    argocd = {
      principal_arn = "arn:aws:iam::111111111111:role/pay-dev-argocd-controller"
      policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminPolicy"
      scope         = "namespace"
      namespaces    = ["router", "locker", "drainer", "scheduler", "external-secrets", "karpenter", "istio-system", "kyverno"]
    }
  }

  eks_log_retention_days = 30
  # Pool CPU caps sized to the environment; the module default is prod-sized.
  karpenter_cpu_limits = {
    payments = 32
    stateful = 16
    cde      = 16
    workers  = 32
    ci       = 16
    ci-prod  = 8
  }

  aurora_writer_class = "db.r7g.large"
  aurora_reader_class = "db.r7g.large"
  aurora_reader_count = 1
  deletion_protection = false
  memorydb_node_type  = "db.t4g.small"
  memorydb_shards     = 1
  vault_lock_enabled  = false
}
