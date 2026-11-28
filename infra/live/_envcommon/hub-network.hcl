# Hub and spoke: environment transit gateways peer with the shared-services hub; read by tgw-hub, tgw-spoke, admin-edge and the eks units.
locals {
  cfg = yamldecode(file("${get_repo_root()}/config/platform.yaml"))

  hub_vpc_cidr = local.cfg.network.shared_services["eu-central-1"]
  # Private tier of the shared-services VPC (same split as shared-services/eu-central-1/vpc): central nodes, pods and internal NLBs; the untrusted runner tier stays out.
  central_cidrs = [for i in range(3) : cidrsubnet(local.hub_vpc_cidr, 3, i)]

  # Spoke name <env>-<region-short>; the standby region peers directly with the eu-central-1 hub.
  spokes = {
    dev-euc1   = { env = "dev", region = "eu-central-1", account_id = local.cfg.accounts.dev, cidrs = [local.cfg.network.dev["eu-central-1"]] }
    stage-euc1 = { env = "stage", region = "eu-central-1", account_id = local.cfg.accounts.stage, cidrs = [local.cfg.network.stage["eu-central-1"]] }
    prod-euc1  = { env = "prod", region = "eu-central-1", account_id = local.cfg.accounts.prod, cidrs = [local.cfg.network.prod["eu-central-1"]] }
    prod-use1  = { env = "prod", region = "us-east-1", account_id = local.cfg.accounts.prod, cidrs = [local.cfg.network.prod["us-east-1"]] }
  }

  # Node egress beyond HTTPS: Tempo OTLP gRPC and Logstash.
  telemetry_ports = [4317, 8443]
}
