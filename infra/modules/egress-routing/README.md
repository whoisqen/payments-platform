# egress-routing

Routes inside the egress VPC that put the Network Firewall on the only path between the transit gateway and the NAT gateways.
Per AZ: attachment subnets send 0.0.0.0/0 to the firewall endpoint of that AZ, firewall subnets send 0.0.0.0/0 to the NAT gateway of that AZ
and `workload_cidrs` to the transit gateway, NAT subnets send `workload_cidrs` back to the same firewall endpoint (symmetric, stateful inspection works).
The NAT subnets need one route table per AZ (vpc `public_route_table_per_az`). Inputs come from the egress-vpc, firewall and tgw stacks.
Test: `terraform init -backend=false && terraform test`.
