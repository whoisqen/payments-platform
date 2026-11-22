module "kms" {
  source      = "../../../../../../../../../tmp/overlay/infra/modules/kms-set"
  account_id  = local.account_id
  region      = "eu-central-1"
  environment = "dev"
  keys        = local.kms_keys
  tags        = { team = "platform", owner = local.owner, pci-scope = "cde", data-class = "card-data", backup-tier = "none" }
}

module "eks" {
  source                   = "../../../../../../../../../tmp/overlay/infra/modules/eks"
  region                   = "eu-central-1"
  environment              = "dev"
  component                = "eks-cell-0"
  kubernetes_version       = local.kubernetes_version
  vpc_id                   = "vpc-1"
  vpc_cidr_block           = local.vpc_cidrs["eu-central-1"]
  subnet_ids               = [for i in range(3) : "subnet-${i}"]
  secrets_kms_key_arn      = module.kms.key_arns["cell-0"]
  logs_kms_key_arn         = module.kms.key_arns["logs"]
  ebs_kms_key_arn          = module.kms.key_arns["ebs-nodes"]
  permissions_boundary_arn = local.permissions_boundary_arn
  access_entries           = local.access_entries
  tags                     = { team = "platform", owner = local.owner, pci-scope = "cde", data-class = "internal", backup-tier = "none" }
}

module "memorydb" {
  source             = "../../../../../../../../../tmp/overlay/infra/modules/memorydb"
  env                = "dev"
  region_short       = "euc1"
  component          = "memorydb-cell-0"
  kms_key_arn        = module.kms.key_arns["cell-0"]
  subnet_ids         = [for i in range(3) : "subnet-${i}"]
  security_group_ids = ["sg-1"]
  node_type          = local.memorydb_node_type
  num_shards         = local.memorydb_shards
  users              = local.memorydb_users
  tags               = { team = "payments-core", owner = local.owner, pci-scope = "cde", data-class = "pii", backup-tier = "silver" }
}

module "iam" {
  source                          = "../../../../../../../../../tmp/overlay/infra/modules/iam-workloads"
  region                          = "eu-central-1"
  environment                     = "dev"
  cell                            = "cell-0"
  account_id                      = local.account_id
  cluster_name                    = module.eks.cluster_name
  cluster_arn                     = module.eks.cluster_arn
  permissions_boundary_arn        = local.permissions_boundary_arn
  deny_recovery_writes_policy_arn = "arn:aws:iam::111111111111:policy/x"
  memorydb                        = { cluster_arn = module.memorydb.cluster_arn, users = { for u, _ in local.memorydb_users : u => u } }
  rds_db_connect_arns             = {}
  locker_kms_key_arn              = module.kms.key_arns["locker"]
  secrets_kms_key_arn             = module.kms.key_arns["shared"]
  secret_arns                     = ["arn:aws:secretsmanager:eu-central-1:111111111111:secret:x"]
  dynamodb_table_arn              = "arn:aws:dynamodb:eu-central-1:111111111111:table/x"
  tags                            = { team = "payments-core", owner = local.owner, pci-scope = "cde", data-class = "internal", backup-tier = "none" }
}

module "karpenter" {
  source                   = "../../../../../../../../../tmp/overlay/infra/modules/karpenter"
  region                   = "eu-central-1"
  account_id               = local.account_id
  cluster_name             = module.eks.cluster_name
  permissions_boundary_arn = local.permissions_boundary_arn
  ebs_kms_key_arn          = module.kms.key_arns["ebs-nodes"]
  subnet_ids               = [for i in range(3) : "subnet-${i}"]
  security_group_ids       = [module.eks.node_security_group_id]
  bottlerocket_version     = local.bottlerocket_version
  tags                     = { team = "platform", owner = local.owner, pci-scope = "cde", data-class = "internal", backup-tier = "none" }
  extra_node_tags          = { environment = "dev", cell = "cell-0" }
}
