# Profile of the shared clusters (locker, edge, control-center); the envcommons of this directory read it, the unit path selects the cluster.
locals {
  path    = regex("/live/(?P<env>[^/]+)/(?P<region>[^/]+)/(?P<cluster>locker|edge|control-center)/", get_original_terragrunt_dir())
  env_cfg = read_terragrunt_config("${get_repo_root()}/infra/live/${local.path.env}/env.hcl").locals
  working = local.path.region == local.env_cfg.cfg.regions.working

  # Node pool caps follow config/environments: the working region uses eks.cpu_limits, the standby region standby.node_pool_cpu_limits;
  # <cluster>_eks.cpu_limits in config/environments replaces the derived caps of that cluster.
  base   = local.working ? local.env_cfg.karpenter_cpu_limits : try(local.env_cfg.standby_node_pool, local.env_cfg.karpenter_cpu_limits)
  addons = min(local.base.workers, 32)

  profiles = {
    # Card vault: every node holds card data, so no pool may use Spot (PCI DSS, D-section 4).
    locker = {
      team     = "payments-core", pci_scope = "cde", data_class = "card-data", secrets_key = "locker"
      pools    = ["cde", "workers"], cpu = { cde = local.base.cde, workers = local.addons }, spot_pools = [], workers_spot = false
      services = ["locker"]
    }
    # Payments gateway in front of the cells: card data passes through it, so it stays On-Demand as well.
    edge = {
      team     = "platform", pci_scope = "cde", data_class = "card-data", secrets_key = "shared"
      pools    = ["payments", "workers"], cpu = { payments = local.base.payments, workers = local.addons }, spot_pools = [], workers_spot = false
      services = []
    }
    # Merchant dashboard: outside the CDE, so its workers pool may use Spot like every workers pool.
    control-center = {
      team     = "payments-core", pci_scope = "out-of-scope", data_class = "internal", secrets_key = "shared"
      pools    = ["workers"], cpu = { workers = local.addons }, spot_pools = [], workers_spot = true
      services = []
    }
  }

  profile    = local.profiles[local.path.cluster]
  cpu_limits = try(local.env_cfg.sizing["${replace(local.path.cluster, "-", "_")}_eks"].cpu_limits, local.profile.cpu)
}
