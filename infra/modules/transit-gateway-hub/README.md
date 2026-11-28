# transit-gateway-hub

Hub side of the hub-and-spoke network: the shared-services transit gateway requests one peering per environment transit gateway in `spokes` (any region; the standby region peers directly).
Every peering is associated with its own route table that holds only `hub_cidrs` to `hub_attachment_id`, so a spoke reaches shared-services and never another spoke.
`hub_route_table_id` (table of the shared-services VPC) gets each spoke's `cidrs` through that spoke's peering; spoke CIDRs must not overlap.
A peering is associated and routed only after `accepted = true`: request here, accept with `transit-gateway-spoke` in the spoke account, then set the flag and apply again.
Test: `terraform init -backend=false && terraform test`.
