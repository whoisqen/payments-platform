locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}

terraform {
  source = "${get_repo_root()}/infra/modules//vpc"
}

inputs = {
  component               = "vpc-egress"
  enable_internet_gateway = true
  flow_logs_bucket_arn    = local.env_cfg.flow_logs_bucket_arn
  # The egress VPC holds no workloads, so it needs no endpoints.
  gateway_endpoint_services   = []
  interface_endpoint_services = []
  cidr_block                  = local.env_cfg.egress_cidr
  # Public tier holds the NAT gateways, private the firewall endpoints and data the transit gateway attachments.
  subnet_cidrs = {
    public  = [for i in range(3) : cidrsubnet(local.env_cfg.egress_cidr, 6, i)]
    private = [for i in range(3) : cidrsubnet(local.env_cfg.egress_cidr, 8, 16 + i)]
    data    = [for i in range(3) : cidrsubnet(local.env_cfg.egress_cidr, 8, 32 + i)]
  }
  tags = {
    team        = "platform"
    owner       = local.env_cfg.owner
    pci-scope   = "connected"
    data-class  = "internal"
    backup-tier = "none"
  }
}
