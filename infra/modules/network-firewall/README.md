# network-firewall

Egress control of the network account: an AWS Network Firewall in three AZs with a strict-order policy that drops
everything except the PSP domains in `psp_domains` (TLS SNI and HTTP host), plus one NAT gateway and one static
Elastic IP per AZ (`egress_public_ips`, registered with every PSP; the EIPs have `prevent_destroy`).
Routing (transit gateway to firewall to NAT) is set by the caller with `firewall_endpoint_ids`; dev maps one firewall subnet, so the caller must route every AZ to that one endpoint.
With `ci_source_cidrs` (the CI VPC) a CI allowlist (`ci_domains`: GitHub, Actions storage, Auto Scaling API, package registries) follows at priority 4, HOME_NET limited to those CIDRs; `ci_trusted_source_cidrs` (trusted pools) also pass `ci_trusted_domains` (AWS APIs, pass-only rules, priority 3) and `platform_domains` (run-time needs of the private tier, such as grafana.com); `psp_domains` may then be empty.
With `enable_logging`, ALERT and FLOW logs go to `log_bucket_name`. Recovery regions run the same module with their own EIPs.
Test: `terraform init -backend=false && terraform test`.
