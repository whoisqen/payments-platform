# admin-edge

Internal entry to the admin tools (Argo CD, Vault, Alertmanager, VictoriaMetrics, Prometheus, Sentry, Grafana) in the shared-services account.

- Private Route 53 zone `zone_name` (`dns.admin_zone`) attached to every VPC in `vpc_ids`; `spoke_vpcs` authorizes the environment VPCs, which associate from their own account (`transit-gateway-spoke`). Nothing else resolves it.
- `nlb_security_group`: security group of the internal NLBs, environment CIDRs on 443, 4317 and 8443 only, this VPC on 443; output `nlb_security_group_id` goes into the Gateway annotation `aws-load-balancer-security-groups`.
- Wildcard alias `*.<zone>` to the internal NLB. The AWS Load Balancer Controller builds the NLB from the Gateway, so Terraform finds it by the tag `service.k8s.aws/stack` (`nlb_stack_tag`, `namespace/gateway-name`). Apply in two steps: first with `nlb_lookup_enabled = false` (zone, CA, roles), then, once the Gateway has a load balancer, with `true` and `nlb_stack_tag` set.
- AWS Private CA, root, short-lived certificates, revocation off (certificates are renewed by cert-manager before they matter). The CA key is held by the service in its HSM; Private CA does not take a customer managed KMS key. The root certificate is issued and installed by this module.
- Pod Identity roles, both under the permissions boundary:
  - `load-balancer-controller` (default `kube-system/aws-load-balancer-controller`): the standard controller policy, with every write limited to resources tagged `elbv2.k8s.aws/cluster = <cluster_name>`.
  - `privateca-issuer` (default `cert-manager/aws-privateca-issuer`): `acm-pca:IssueCertificate`, `GetCertificate`, `DescribeCertificateAuthority` on the CA of this module only.
- Outputs: `zone_id`, `zone_name`, `wildcard_fqdn`, `wildcard_record_created`, `ca_arn`, `role_arns`.

Tags: `tags` must carry team, owner, pci-scope, data-class and backup-tier; the rest come from Terragrunt `default_tags`.

Test: `terraform init -backend=false && terraform test` (mock providers).
