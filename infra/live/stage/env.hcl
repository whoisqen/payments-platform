# Placeholders: account IDs, CIDRs, ARNs and domains below are replaced by the real values after the AFT accounts and IPAM exist.
locals {
  environment                = "stage"
  account_id                 = "333333333333"
  shared_services_account_id = "222222222222"
  owner                      = "platform@example.com"
  cost_center                = "cc-stage"

  # Output state_kms_key_arn of infra/bootstrap.
  state_kms_key_arn        = "arn:aws:kms:eu-central-1:222222222222:key/mrk-00000000000000000000000000000000"
  permissions_boundary_arn = "arn:aws:iam::333333333333:policy/workload-boundary"
  flow_logs_bucket_arn     = "arn:aws:s3:::pay-stage-log-archive-flow-logs"
  autoscaling_slr_arn      = "arn:aws:iam::333333333333:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"

  kubernetes_version   = "1.34"
  bottlerocket_version = "v1.49.0"

  azs = {
    "eu-central-1" = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
    "us-east-1"    = ["us-east-1a", "us-east-1b", "us-east-1c"]
    "us-east-2"    = ["us-east-2a", "us-east-2b", "us-east-2c"]
  }

  vpc_cidrs = {
    "eu-central-1" = "10.130.0.0/16"
    "us-east-1"    = "10.131.0.0/16"
    "us-east-2"    = "10.132.0.0/16"
  }
  egress_cidr = "10.133.0.0/20"

  # Set after the first apply of tgw: the vpc stack needs the attachment before it may route through it (two-step by design).
  transit_gateway_id = null

  psp_domains = [".psp-sandbox.example.com"]
  zone_name   = "stage.pay.example.com"

  cells = ["cell-0", "cell-1", "cell-2", "cell-3", "spare"]
  kms_keys = merge(
    {
      "ebs-nodes" = { user_role_arns = ["arn:aws:iam::333333333333:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"] }
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
      principal_arn = "arn:aws:iam::333333333333:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_SRE-View"
      policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
    }
    argocd = {
      principal_arn = "arn:aws:iam::333333333333:role/pay-stage-argocd-controller"
      policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminPolicy"
      scope         = "namespace"
      namespaces    = ["router", "locker", "drainer", "scheduler", "external-secrets", "karpenter", "istio-system", "kyverno"]
    }
  }

  eks_log_retention_days = 365
  # Pool CPU caps sized to the environment; the module default is prod-sized.
  karpenter_cpu_limits = {
    payments = 100
    stateful = 50
    cde      = 50
    workers  = 100
    ci       = 32
    ci-prod  = 16
  }

  aurora_writer_class = "db.r7g.xlarge"
  aurora_reader_class = "db.r7g.xlarge"
  aurora_reader_count = 1
  deletion_protection = true
  memorydb_node_type  = "db.r7g.large"
  memorydb_shards     = 2
  vault_lock_enabled  = false
}
