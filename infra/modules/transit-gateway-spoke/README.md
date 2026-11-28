# transit-gateway-spoke

Spoke side of the hub-and-spoke network: accepts the peering that `transit-gateway-hub` requested from shared-services.
The peering is associated with its own route table `pay-<env>-<region-short>-tgw-spoke` that holds only `vpc_cidrs` to the workload attachment, so the hub reaches this VPC and nothing else here.
The workload table (`cde`) gets `hub_cidrs` through the peering; those routes are more specific than its egress default.
`admin_zone_id` with `vpc_id` associates the workload VPC with the admin zone of shared-services (Vault, the admin hosts) after admin-edge authorized it.
Test: `terraform init -backend=false && terraform test`.
