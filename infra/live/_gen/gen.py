#!/usr/bin/env python3
"""Temporary generator of infra/live; deleted before the report."""
import os, shutil

W = "/data/vlad/portfolio/payments-platform/.claude/worktrees/agent-ae6ce5dd4f5691ab7/infra/live"
ENVS = {
    "dev": dict(account="111111111111", shared="222222222222", octet=120, writer="db.r7g.large", reader="db.r7g.large",
                readers=1, delete_protection="false", mem_node="db.t4g.small", shards=1, vault_lock="false"),
    "stage": dict(account="333333333333", shared="222222222222", octet=130, writer="db.r7g.xlarge", reader="db.r7g.xlarge",
                  readers=1, delete_protection="true", mem_node="db.r7g.large", shards=2, vault_lock="false"),
}
CELLS = ["cell-0", "cell-1", "cell-2", "cell-3", "spare"]
WORK = "eu-central-1"
REC = ["us-east-1", "us-east-2"]
KEYS = ["ebs-nodes", "logs", "shared", "locker", "backup"] + CELLS
MODE = '["init", "validate", "plan"]'


def w(path, text):
    p = os.path.join(W, path)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w") as f:
        f.write(text)


def env_hcl(env, c):
    o = c["octet"]
    cells = "[" + ", ".join(f'"{x}"' for x in CELLS) + "]"
    return f'''# Placeholders: account IDs, CIDRs, ARNs and domains below are replaced by the real values after the AFT accounts and IPAM exist.
locals {{
  environment                = "{env}"
  account_id                 = "{c["account"]}"
  shared_services_account_id = "{c["shared"]}"
  owner                      = "platform@example.com"
  cost_center                = "cc-{env}"

  # Output state_kms_key_arn of infra/bootstrap.
  state_kms_key_arn        = "arn:aws:kms:eu-central-1:{c["shared"]}:key/mrk-00000000000000000000000000000000"
  permissions_boundary_arn = "arn:aws:iam::{c["account"]}:policy/workload-boundary"
  flow_logs_bucket_arn     = "arn:aws:s3:::pay-{env}-log-archive-flow-logs"
  autoscaling_slr_arn      = "arn:aws:iam::{c["account"]}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"

  kubernetes_version   = "1.34"
  bottlerocket_version = "v1.49.0"

  azs = {{
    "eu-central-1" = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
    "us-east-1"    = ["us-east-1a", "us-east-1b", "us-east-1c"]
    "us-east-2"    = ["us-east-2a", "us-east-2b", "us-east-2c"]
  }}

  vpc_cidrs = {{
    "eu-central-1" = "10.{o}.0.0/16"
    "us-east-1"    = "10.{o + 1}.0.0/16"
    "us-east-2"    = "10.{o + 2}.0.0/16"
  }}
  egress_cidr = "10.{o + 3}.0.0/20"

  # Set after the first apply of tgw: the vpc stack needs the attachment before it may route through it (two-step by design).
  transit_gateway_id = null

  psp_domains = [".psp-sandbox.example.com"]
  zone_name   = "{env}.pay.example.com"

  cells = {cells}
  kms_keys = merge(
    {{
      "ebs-nodes" = {{ user_role_arns = ["arn:aws:iam::{c["account"]}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"] }}
      "logs"      = {{ service_principals = ["logs.amazonaws.com"] }}
      "shared"    = {{}}
      "locker"    = {{}}
      "backup"    = {{}}
    }},
    {{ for c in {cells} : c => {{}} }},
  )

  memorydb_users = {{
    router    = "on ~* &* +@all -@admin -@dangerous"
    drainer   = "on ~* &* +@all -@admin -@dangerous"
    scheduler = "on ~* &* +@all -@admin -@dangerous"
  }}

  # People get view only; ArgoCD is limited to the platform namespaces and never cluster-admin.
  access_entries = {{
    sre-view = {{
      principal_arn = "arn:aws:iam::{c["account"]}:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_SRE-View"
      policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
    }}
    argocd = {{
      principal_arn = "arn:aws:iam::{c["account"]}:role/pay-{env}-argocd-controller"
      policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminPolicy"
      scope         = "namespace"
      namespaces    = ["router", "locker", "drainer", "scheduler", "external-secrets", "karpenter", "istio-system", "kyverno"]
    }}
  }}

  aurora_writer_class = "{c["writer"]}"
  aurora_reader_class = "{c["reader"]}"
  aurora_reader_count = {c["readers"]}
  deletion_protection = {c["delete_protection"]}
  memorydb_node_type  = "{c["mem_node"]}"
  memorydb_shards     = {c["shards"]}
  vault_lock_enabled  = {c["vault_lock"]}
}}
'''


def tags(team, scope, data, backup):
    return f'''  tags = {{
    team        = "{team}"
    owner       = local.env_cfg.owner
    pci-scope   = "{scope}"
    data-class  = "{data}"
    backup-tier = "{backup}"
  }}'''


def common(module, body, tag):
    return f'''locals {{
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}}

terraform {{
  source = "${{get_repo_root()}}/infra/modules//{module}"
}}

inputs = {{
{body}{tag}
}}
'''


T = tags
COMMON = {}
COMMON["foundation/kms"] = common("kms-set", "  keys = local.env_cfg.kms_keys\n", T("platform", "cde", "card-data", "none"))
COMMON["foundation/vpc"] = common("vpc", '''  component            = "vpc-cde"
  flow_logs_bucket_arn = local.env_cfg.flow_logs_bucket_arn
''', T("platform", "cde", "internal", "none"))
COMMON["foundation/egress-vpc"] = common("vpc", '''  component               = "vpc-egress"
  enable_internet_gateway = true
  flow_logs_bucket_arn    = local.env_cfg.flow_logs_bucket_arn
  cidr_block              = local.env_cfg.egress_cidr
  # Public tier holds the NAT gateways, private the firewall endpoints and data the transit gateway attachments.
  subnet_cidrs = {
    public  = [for i in range(3) : cidrsubnet(local.env_cfg.egress_cidr, 6, i)]
    private = [for i in range(3) : cidrsubnet(local.env_cfg.egress_cidr, 8, 16 + i)]
    data    = [for i in range(3) : cidrsubnet(local.env_cfg.egress_cidr, 8, 32 + i)]
  }
''', T("platform", "connected", "internal", "none"))
COMMON["foundation/tgw"] = common("transit-gateway", '''  route_tables = ["cde", "egress"]
  static_routes = [
    { route_table = "cde", cidr = "0.0.0.0/0", attachment = "egress" },
  ]
''', T("platform", "connected", "internal", "none"))
COMMON["foundation/firewall"] = common("network-firewall", '''  psp_domains       = local.env_cfg.psp_domains
  delete_protection = local.env_cfg.deletion_protection
''', T("security", "connected", "internal", "none"))
COMMON["foundation/ecr"] = common("ecr", '''  account_id = local.env_cfg.account_id
''', T("platform", "connected", "internal", "none"))
COMMON["data/data-access"] = common("data-access", "", T("payments-core", "cde", "internal", "none"))
COMMON["data/aurora"] = common("aurora-global", '''  backup_retention_days = 35
  deletion_protection   = local.env_cfg.deletion_protection
  writer_instance_class = local.env_cfg.aurora_writer_class
  reader_instance_class = local.env_cfg.aurora_reader_class
  reader_count          = local.env_cfg.aurora_reader_count
''', T("payments-core", "cde", "card-data", "gold"))
COMMON["data/memorydb"] = common("memorydb", '''  node_type  = local.env_cfg.memorydb_node_type
  num_shards = local.env_cfg.memorydb_shards
  users      = local.env_cfg.memorydb_users
''', T("payments-core", "cde", "pii", "silver"))
COMMON["data/dynamodb"] = common("dynamodb-global", '''  deletion_protection = local.env_cfg.deletion_protection
''', T("payments-core", "cde", "internal", "gold"))
COMMON["data/secrets"] = common("secrets-replica", '''  secrets = {
    router         = { description = "Router configuration and PSP credentials" }
    locker         = { description = "Locker configuration" }
    drainer        = { description = "Drainer configuration" }
    scheduler      = { description = "Scheduler configuration" }
    control-center = { description = "Control center configuration" }
  }
''', T("security", "cde", "internal", "silver"))
COMMON["data/s3-backup"] = common("s3-backup", "", T("platform", "cde", "card-data", "gold"))
COMMON["data/backup"] = common("backup", '''  vault_lock_enabled = local.env_cfg.vault_lock_enabled
  source_account_ids = [local.env_cfg.account_id]
''', T("platform", "cde", "card-data", "none"))
COMMON["compute/eks"] = common("eks", '''  kubernetes_version       = local.env_cfg.kubernetes_version
  permissions_boundary_arn = local.env_cfg.permissions_boundary_arn
  access_entries           = local.env_cfg.access_entries
''', T("platform", "cde", "internal", "none"))
COMMON["compute/karpenter"] = common("karpenter", '''  bottlerocket_version     = local.env_cfg.bottlerocket_version
  permissions_boundary_arn = local.env_cfg.permissions_boundary_arn
''', T("platform", "cde", "internal", "none"))
COMMON["compute/iam-workloads"] = common("iam-workloads", '''  permissions_boundary_arn = local.env_cfg.permissions_boundary_arn
''', T("payments-core", "cde", "internal", "none"))
COMMON["edge/accelerator"] = common("global-accelerator", '''  endpoint_groups = {
    "eu-central-1" = { active = true }
    "us-east-1"    = { active = false }
    "us-east-2"    = { active = false }
  }
''', T("platform", "connected", "public", "none"))
COMMON["edge/dns"] = common("dns-certs", '''  zone_name = local.env_cfg.zone_name
  certificates = {
    api = { domain_name = "api.${local.env_cfg.zone_name}" }
  }
''', T("platform", "connected", "public", "none"))


def arn(svc, tail, region="eu-central-1"):
    return f"arn:aws:{svc}:{region}:000000000000:{tail}"


def subnets(p):
    return "[" + ", ".join(f'"subnet-{p}{i}0000000"' for i in range(3)) + "]"


def mock(kind, region=WORK):
    if kind == "kms":
        keys = "\n".join(f'      "{k}" = "{arn("kms", "key/mrk-" + k, region)}"' for k in KEYS)
        return f"    key_arns = {{\n{keys}\n    }}"
    if kind in ("vpc", "egress-vpc"):
        return ('    vpc_id         = "vpc-00000000"\n    vpc_cidr_block = "10.0.0.0/16"\n    subnet_ids = {\n'
                f'      public  = {subnets("a")}\n      private = {subnets("b")}\n      data    = {subnets("c")}\n    }}')
    if kind == "eks":
        return (f'    cluster_name           = "pay-mock-euc1-eks"\n    cluster_arn            = "{arn("eks", "cluster/pay-mock-euc1-eks")}"\n'
                '    node_security_group_id = "sg-00000000"')
    if kind == "data-access":
        return ('    security_group_ids = {\n      aurora       = "sg-00000001"\n      aurora-proxy = "sg-00000002"\n      memorydb     = "sg-00000003"\n    }\n'
                '    db_subnet_group_name = "mock"')
    if kind == "aurora":
        return '    global_cluster_id = "pay-mock-euc1-aurora"'
    if kind == "memorydb":
        return f'    cluster_arn = "{arn("memorydb", "cluster/mock")}"'
    if kind == "dynamodb":
        return (f'    table_arn                       = "{arn("dynamodb", "table/mock")}"\n'
                '    deny_recovery_writes_policy_arn = "arn:aws:iam::000000000000:policy/mock"')
    if kind == "secrets":
        return f'    secret_arns = {{\n      router = "{arn("secretsmanager", "secret:mock-AbCdEf")}"\n    }}'
    raise KeyError(kind)


def dep(name, path, kind, region=WORK):
    return f'''dependency "{name}" {{
  config_path = "{path}"

  mock_outputs = {{
{mock(kind, region)}
  }}
  mock_outputs_allowed_terraform_commands = {MODE}
}}
'''


def stack(group, name, deps, inputs):
    body = f'''include "root" {{
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}}

include "envcommon" {{
  path   = "${{dirname(find_in_parent_folders("terragrunt.hcl"))}}/_envcommon/{group}/{name}.hcl"
  expose = true
}}

'''
    body += "\n".join(deps) + ("\n" if deps else "")
    body += "inputs = {\n" + inputs + "}\n"
    return body


CFG = "include.envcommon.locals.env_cfg"


def subnets_block(cidr_):
    return f'''  subnet_cidrs = {{
    public  = [for i in range(3) : cidrsubnet({cidr_}, 8, 99 + i)]
    private = [for i in range(3) : cidrsubnet({cidr_}, 3, i)]
    data    = [for i in range(3) : cidrsubnet({cidr_}, 8, 96 + i)]
  }}
'''


def gen_env(env, c):
    base = env
    w(f"{base}/env.hcl", env_hcl(env, c))
    azs = lambda r: f'{CFG}.azs["{r}"]'
    r = WORK
    P = f"{base}/{r}"
    rec_kms = [dep("kms_use1", "../../us-east-1/kms", "kms", "us-east-1"), dep("kms_use2", "../../us-east-2/kms", "kms", "us-east-2")]

    def rec(key):
        return (f'    "us-east-1" = {{ short = "use1", kms_key_arn = dependency.kms_use1.outputs.key_arns["{key}"] }}\n'
                f'    "us-east-2" = {{ short = "use2", kms_key_arn = dependency.kms_use2.outputs.key_arns["{key}"] }}')

    w(f"{P}/kms/terragrunt.hcl", stack("foundation", "kms", [], ""))
    cidr = f'{CFG}.vpc_cidrs["{r}"]'
    w(f"{P}/vpc/terragrunt.hcl", stack("foundation", "vpc", [], f'''  cidr_block = {cidr}
  azs        = {azs(r)}
{subnets_block(cidr)}  enable_egress_route        = {CFG}.transit_gateway_id != null
  egress_transit_gateway_id = {CFG}.transit_gateway_id
'''))
    w(f"{P}/egress-vpc/terragrunt.hcl", stack("foundation", "egress-vpc", [], f"  azs = {azs(r)}\n"))
    w(f"{P}/tgw/terragrunt.hcl", stack("foundation", "tgw", [dep("vpc", "../vpc", "vpc"), dep("egress_vpc", "../egress-vpc", "egress-vpc")], '''  attachments = {
    cde = {
      vpc_id       = dependency.vpc.outputs.vpc_id
      subnet_ids   = dependency.vpc.outputs.subnet_ids["data"]
      route_table  = "cde"
      propagate_to = ["egress"]
    }
    egress = {
      vpc_id         = dependency.egress_vpc.outputs.vpc_id
      subnet_ids     = dependency.egress_vpc.outputs.subnet_ids["data"]
      route_table    = "egress"
      appliance_mode = true
    }
  }
'''))
    w(f"{P}/firewall/terragrunt.hcl", stack("foundation", "firewall", [dep("egress_vpc", "../egress-vpc", "egress-vpc")], '''  vpc_id              = dependency.egress_vpc.outputs.vpc_id
  firewall_subnet_ids = dependency.egress_vpc.outputs.subnet_ids["private"]
  nat_subnet_ids      = dependency.egress_vpc.outputs.subnet_ids["public"]
'''))
    w(f"{P}/ecr/terragrunt.hcl", stack("foundation", "ecr", [dep("kms", "../kms", "kms")], '''  repositories        = ["router", "locker", "drainer", "scheduler", "control-center"]
  kms_key_arn         = dependency.kms.outputs.key_arns["shared"]
  replication_regions = ["us-east-1", "us-east-2"]
'''))
    for comp, d in (("backup", "s3-backup"), ("event-archive", "s3-event-archive")):
        w(f"{P}/{d}/terragrunt.hcl", stack("data", "s3-backup", [dep("kms", "../kms", "kms")] + rec_kms, f'''  component   = "{comp}"
  kms_key_arn = dependency.kms.outputs.key_arns["shared"]
  recovery_regions = {{
{rec("shared")}
  }}
'''))
    cell_keys = "\n".join(f'    dependency.kms.outputs.key_arns["{x}"],' for x in CELLS)
    w(f"{P}/backup/terragrunt.hcl", stack("data", "backup", [dep("kms", "../kms", "kms")] + rec_kms, f'''  kms_key_arn = dependency.kms.outputs.key_arns["backup"]
  data_kms_key_arns = [
    dependency.kms.outputs.key_arns["shared"],
    dependency.kms.outputs.key_arns["locker"],
{cell_keys}
  ]
  recovery_regions = {{
{rec("backup")}
  }}
'''))
    w(f"{P}/secrets/terragrunt.hcl", stack("data", "secrets", [dep("kms", "../kms", "kms")] + rec_kms, '''  kms_key_arn = dependency.kms.outputs.key_arns["shared"]
  recovery_regions = {
    "us-east-1" = { kms_key_arn = dependency.kms_use1.outputs.key_arns["shared"] }
    "us-east-2" = { kms_key_arn = dependency.kms_use2.outputs.key_arns["shared"] }
  }
'''))
    w(f"{P}/dynamodb/terragrunt.hcl", stack("data", "dynamodb", [dep("kms", "../kms", "kms")] + rec_kms, '''  kms_key_arn = dependency.kms.outputs.key_arns["shared"]
  recovery_regions = {
    "us-east-1" = { kms_key_arn = dependency.kms_use1.outputs.key_arns["shared"] }
    "us-east-2" = { kms_key_arn = dependency.kms_use2.outputs.key_arns["shared"] }
  }
'''))
    w(f"{P}/edge-accelerator/terragrunt.hcl", stack("edge", "accelerator", [], ""))
    w(f"{P}/edge-dns/terragrunt.hcl", stack("edge", "dns", [], ""))

    for n, cell in enumerate(CELLS):
        C = f"{P}/{cell}"
        w(f"{C}/eks/terragrunt.hcl", stack("compute", "eks", [dep("vpc", "../../vpc", "vpc"), dep("kms", "../../kms", "kms")], f'''  component           = "eks-{cell}"
  vpc_id              = dependency.vpc.outputs.vpc_id
  vpc_cidr_block      = dependency.vpc.outputs.vpc_cidr_block
  subnet_ids          = dependency.vpc.outputs.subnet_ids["private"]
  secrets_kms_key_arn = dependency.kms.outputs.key_arns["{cell}"]
  logs_kms_key_arn    = dependency.kms.outputs.key_arns["logs"]
  ebs_kms_key_arn     = dependency.kms.outputs.key_arns["ebs-nodes"]
'''))
        w(f"{C}/karpenter/terragrunt.hcl", stack("compute", "karpenter", [dep("vpc", "../../vpc", "vpc"), dep("kms", "../../kms", "kms"), dep("eks", "../eks", "eks")], f'''  cluster_name       = dependency.eks.outputs.cluster_name
  ebs_kms_key_arn    = dependency.kms.outputs.key_arns["ebs-nodes"]
  subnet_ids         = dependency.vpc.outputs.subnet_ids["private"]
  security_group_ids = [dependency.eks.outputs.node_security_group_id]
  extra_node_tags = {{
    environment = include.root.locals.env
    cell        = include.root.locals.cell
    component   = "karpenter-nodes"
    managed-by  = "argocd"
    repo        = "infra/modules/karpenter"
    cost-center = {CFG}.cost_center
  }}
'''))
        w(f"{C}/data-access/terragrunt.hcl", stack("data", "data-access", [dep("vpc", "../../vpc", "vpc"), dep("eks", "../eks", "eks")], '''  component                 = "data-''' + cell + '''"
  vpc_id                    = dependency.vpc.outputs.vpc_id
  data_subnet_ids           = dependency.vpc.outputs.subnet_ids["data"]
  client_security_group_ids = [dependency.eks.outputs.node_security_group_id]
  stores = {
    aurora       = { port = 5432, clients = "aurora-proxy" }
    aurora-proxy = { port = 5432, clients = "workload" }
    memorydb     = { port = 6379, clients = "workload" }
  }
'''))
        w(f"{C}/aurora/terragrunt.hcl", stack("data", "aurora", [dep("vpc", "../../vpc", "vpc"), dep("kms", "../../kms", "kms"), dep("data_access", "../data-access", "data-access")], f'''  component                = "aurora-{cell}"
  kms_key_arn              = dependency.kms.outputs.key_arns["{cell}"]
  db_subnet_group_name     = dependency.data_access.outputs.db_subnet_group_name
  security_group_ids       = [dependency.data_access.outputs.security_group_ids["aurora"]]
  proxy_security_group_ids = [dependency.data_access.outputs.security_group_ids["aurora-proxy"]]
  proxy_subnet_ids         = dependency.vpc.outputs.subnet_ids["data"]
  availability_zones       = {azs(r)}
  # Writers rotate over the AZs so that one AZ loss never takes every writer.
  writer_az = {azs(r)}[{n % 3}]
'''))
        w(f"{C}/memorydb/terragrunt.hcl", stack("data", "memorydb", [dep("vpc", "../../vpc", "vpc"), dep("kms", "../../kms", "kms"), dep("data_access", "../data-access", "data-access")], f'''  component          = "memorydb-{cell}"
  kms_key_arn        = dependency.kms.outputs.key_arns["{cell}"]
  subnet_ids         = dependency.vpc.outputs.subnet_ids["data"]
  security_group_ids = [dependency.data_access.outputs.security_group_ids["memorydb"]]
'''))
        w(f"{C}/iam-workloads/terragrunt.hcl", stack("compute", "iam-workloads", [
            dep("eks", "../eks", "eks"), dep("kms", "../../kms", "kms"), dep("memorydb", "../memorydb", "memorydb"),
            dep("dynamodb", "../../dynamodb", "dynamodb"), dep("secrets", "../../secrets", "secrets")], f'''  cell                            = "{cell}"
  cluster_name                    = dependency.eks.outputs.cluster_name
  cluster_arn                     = dependency.eks.outputs.cluster_arn
  deny_recovery_writes_policy_arn = dependency.dynamodb.outputs.deny_recovery_writes_policy_arn
  dynamodb_table_arn              = dependency.dynamodb.outputs.table_arn
  locker_kms_key_arn              = dependency.kms.outputs.key_arns["locker"]
  secrets_kms_key_arn             = dependency.kms.outputs.key_arns["shared"]
  secret_arns                     = values(dependency.secrets.outputs.secret_arns)
  memorydb = {{
    cluster_arn = dependency.memorydb.outputs.cluster_arn
    users       = {{ for u, _ in {CFG}.memorydb_users : u => u }}
  }}
  # The aurora-global module does not export the proxy resource id yet, so rds-db:connect ARNs stay empty.
  rds_db_connect_arns = {{}}
'''))

    L = f"{P}/locker"
    eks_deps = [dep(f"eks_{x.replace('-', '_')}", f"../../{x}/eks", "eks") for x in CELLS]
    eks_sgs = "\n".join(f'    dependency.eks_{x.replace("-", "_")}.outputs.node_security_group_id,' for x in CELLS)
    w(f"{L}/data-access/terragrunt.hcl", stack("data", "data-access", [dep("vpc", "../../vpc", "vpc")] + eks_deps, f'''  component       = "data-locker"
  vpc_id          = dependency.vpc.outputs.vpc_id
  data_subnet_ids = dependency.vpc.outputs.subnet_ids["data"]
  client_security_group_ids = [
{eks_sgs}
  ]
  stores = {{
    aurora       = {{ port = 5432, clients = "aurora-proxy" }}
    aurora-proxy = {{ port = 5432, clients = "workload" }}
  }}
'''))
    w(f"{L}/aurora/terragrunt.hcl", stack("data", "aurora", [dep("vpc", "../../vpc", "vpc"), dep("kms", "../../kms", "kms"), dep("data_access", "../data-access", "data-access")], f'''  component                = "aurora-locker"
  kms_key_arn              = dependency.kms.outputs.key_arns["locker"]
  db_subnet_group_name     = dependency.data_access.outputs.db_subnet_group_name
  security_group_ids       = [dependency.data_access.outputs.security_group_ids["aurora"]]
  proxy_security_group_ids = [dependency.data_access.outputs.security_group_ids["aurora-proxy"]]
  proxy_subnet_ids         = dependency.vpc.outputs.subnet_ids["data"]
  availability_zones       = {azs(r)}
  writer_az                = {azs(r)}[2]
'''))

    for rr in REC:
        R = f"{base}/{rr}"
        w(f"{R}/kms/terragrunt.hcl", stack("foundation", "kms", [dep("primary", "../../eu-central-1/kms", "kms")], '''  is_replica       = true
  primary_key_arns = dependency.primary.outputs.key_arns
'''))
        cr = f'{CFG}.vpc_cidrs["{rr}"]'
        w(f"{R}/vpc/terragrunt.hcl", stack("foundation", "vpc", [], f'''  cidr_block = {cr}
  azs        = {azs(rr)}
{subnets_block(cr)}'''))
        w(f"{R}/ecr/terragrunt.hcl", stack("foundation", "ecr", [dep("kms", "../kms", "kms", rr)], '''  create_replica_template = true
  replica_kms_key_arn     = dependency.kms.outputs.key_arns["shared"]
'''))
        for scope in CELLS + ["locker"]:
            D = f"{R}/{scope}"
            w(f"{D}/data-access/terragrunt.hcl", stack("data", "data-access", [dep("vpc", "../../vpc", "vpc")], f'''  component       = "data-{scope}"
  vpc_id          = dependency.vpc.outputs.vpc_id
  data_subnet_ids = dependency.vpc.outputs.subnet_ids["data"]
  # No client group exists before the switch, so nothing can connect to the headless cluster.
  stores = {{
    aurora       = {{ port = 5432, clients = "aurora-proxy" }}
    aurora-proxy = {{ port = 5432, clients = "workload" }}
  }}
'''))
            w(f"{D}/aurora/terragrunt.hcl", stack("data", "aurora", [
                dep("vpc", "../../vpc", "vpc"), dep("kms", "../../kms", "kms", rr), dep("data_access", "../data-access", "data-access"),
                dep("primary", f"../../../eu-central-1/{scope}/aurora", "aurora")], f'''  component                 = "aurora-{scope}"
  region_role               = "recovery"
  global_cluster_identifier = dependency.primary.outputs.global_cluster_id
  kms_key_arn               = dependency.kms.outputs.key_arns["{scope}"]
  db_subnet_group_name      = dependency.data_access.outputs.db_subnet_group_name
  security_group_ids        = [dependency.data_access.outputs.security_group_ids["aurora"]]
  proxy_security_group_ids  = [dependency.data_access.outputs.security_group_ids["aurora-proxy"]]
  proxy_subnet_ids          = dependency.vpc.outputs.subnet_ids["data"]
  availability_zones        = {azs(rr)}
  writer_az                 = {azs(rr)}[0]
'''))


if __name__ == "__main__":
    for e in list(os.listdir(W)):
        if e in ENVS or e == "_envcommon":
            shutil.rmtree(os.path.join(W, e))
    for g, text in COMMON.items():
        w(f"_envcommon/{g}.hcl", text)
    for e, c in ENVS.items():
        gen_env(e, c)
    print("ok")
