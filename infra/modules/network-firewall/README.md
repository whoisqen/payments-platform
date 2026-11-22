# network-firewall

Egress control of the network account: an AWS Network Firewall in three AZs with a strict-order policy that drops
everything except the PSP domains in `psp_domains` (TLS SNI and HTTP host), plus one NAT gateway and one static
Elastic IP per AZ (`egress_public_ips`, registered with every PSP; the EIPs have `prevent_destroy`).
Routing (transit gateway to firewall to NAT) is set by the caller with `firewall_endpoint_ids`.
With `enable_logging`, ALERT and FLOW logs go to `log_bucket_name`. Recovery regions run the same module with their own EIPs.
Test: `terraform init -backend=false && terraform test`.
