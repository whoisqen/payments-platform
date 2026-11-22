from common import a, gap

L = "network"

PROBE = 'probe_success{probe_target="region-health",region="eu-central-1",probe_point="%s"}'
a(layer=L, group="edge", name="RegionDown", sev="critical", team="platform", svc="edge", comp="probes", dash="edge",
  expr='count by (region) (probe_success{probe_target="region-health"} == 0) >= 2', f="2m",
  sum="Region health endpoint fails from at least two of three independent probe points",
  series=[(PROBE % "use1", "0x{n}", "1x{n}"), (PROBE % "use2", "0x{n}", "1x{n}"), (PROBE % "ext", "0x{n}", "1x{n}")],
  labels={"region": "eu-central-1"},
  failure="working region unreachable from two independent probe points", impact="payments fail in the region; input to the switch decision of ADR-015",
  sym="Two or more of the three probe points (us-east-1, us-east-2, external) cannot reach the Frankfurt health endpoint for 2 minutes. This is the detection signal of the semi-automatic switch; inhibits component alerts of the region.",
  diag=["Check `probe_success` per `probe_point`: if only one point fails the cause is the probe path, not the region.", "Check AWS Health and the status of Global Accelerator endpoint groups on the edge dashboard.", "Check the Frankfurt router `up` and ingress NLB target health from the platform dashboard."],
  act=["If the region is confirmed down, the on-call starts the switch: SSM document `pay-runbook-region-down` fences Frankfurt automatically and waits for one on-call confirmation (ADR-015).", "Do not confirm while a single probe point is the only failing one; a false switch with two writers can charge a payment twice.", "If Frankfurt recovers before confirmation, cancel the switch in the document and keep fencing off."],
  esc="Incident commander is added at once; confirmation of the switch needs the commander and the primary.")

a(layer=L, group="edge", name="GlobalAcceleratorEndpointUnhealthy", sev="critical", team="platform", svc="edge", comp="global-accelerator", dash="edge",
  expr="min by (accelerator, endpoint_group) (aws_globalaccelerator_healthy_endpoint_count_minimum) < 1", f="3m",
  sum="Global Accelerator endpoint group has no healthy endpoint",
  series=[('aws_globalaccelerator_healthy_endpoint_count_minimum{accelerator="payments-api",endpoint_group="euc1"}', "0x{n}", "2x{n}")],
  failure="no healthy endpoint behind Global Accelerator", impact="merchant traffic cannot enter the platform",
  sym="The endpoint group of the payments accelerator reports zero healthy endpoints for 3 minutes.",
  diag=["Check the NLB target group health of the affected endpoint group.", "Check router pod readiness per cell: a failed readiness probe removes the NLB targets.", "Compare with `RegionDown`: if it fires too, treat it as a region event."],
  act=["If a bad rollout caused it, roll back the cell through ArgoCD (document `pay-runbook-global-accelerator-endpoint-unhealthy`, step `rollback-cell`).", "If one AZ is affected, cordon the AZ in the NLB with the document step `drain-az`.", "Keep the endpoint group weight unchanged unless the commander orders a switch."],
  esc="Escalate to the AWS Enterprise support case after 15 minutes without recovery.")

a(layer=L, group="edge", name="NatPortAllocationErrors", sev="critical", team="platform", svc="egress", comp="nat-gateway", dash="edge",
  expr="sum by (nat_gateway_id) (rate(aws_natgateway_error_port_allocation_sum[5m])) > 0", f="5m",
  sum="NAT gateway cannot allocate ports, outbound PSP calls fail",
  series=[('aws_natgateway_error_port_allocation_sum{nat_gateway_id="nat-0a1"}', "0+10x{n}", "0+0x{n}")],
  failure="NAT source port exhaustion", impact="calls to PSPs fail from the exhausted gateway, payments go to the unknown state",
  sym="The NAT gateway reports port allocation errors for 5 minutes; outbound connections to PSPs time out.",
  diag=["Check `aws_natgateway_active_connection_count` and the top destinations in the VPC flow logs.", "Check for a retry storm: `retry_total` by dependency on the application dashboard.", "Check whether a recent deploy raised the connection count per pod."],
  act=["Spread egress over more NAT gateways or add EIPs through the Terraform change prepared in `infra/` (document step `scale-egress`).", "If a retry storm is the cause, open the circuit breaker of the PSP with `pay-runbook-nat-port-allocation-errors` step `open-breaker`.", "Never raise retries to compensate; a charge is never retried."],
  esc="Platform primary owns it; payments-core is informed because payments move to the unknown state and sync resolves them.")

a(layer=L, group="certificates", name="CertificateExpiryCritical", sev="critical", team="platform", svc="edge", comp="tls", dash="edge",
  expr="min by (target) (probe_ssl_earliest_cert_expiry) - time() < 14 * 86400", f="10m",
  sum="A public endpoint certificate expires in less than 14 days",
  series=[('probe_ssl_earliest_cert_expiry{target="api.payments.internal",probe_point="use1"}', "864000x{n}", "5184000x{n}")],
  labels={"target": "api.payments.internal"},
  failure="certificate about to expire", impact="merchants and PSP webhooks reject the connection after expiry",
  sym="A certificate seen by the blackbox probes expires within 14 days; automatic renewal did not happen.",
  diag=["Check cert-manager `Certificate` and `CertificateRequest` status for the target.", "Check the ACME or ACM validation DNS records (Route 53).", "Check that the probe sees the same certificate from all three probe points."],
  act=["Force a renewal with the document step `renew-certificate` (cert-manager `cmctl renew` equivalent through the audited workflow).", "If validation fails, fix the DNS record in Terraform and re-run.", "Verify the new expiry from all probe points before closing."],
  esc="Escalate at once when less than 3 days remain.")

a(layer=L, group="edge", name="Route53HealthCheckFailing", sev="critical", team="platform", svc="edge", comp="route53", dash="edge",
  expr="min by (health_check_id) (aws_route53_health_check_status_minimum) < 1", f="3m",
  sum="Route 53 health check reports unhealthy",
  series=[('aws_route53_health_check_status_minimum{health_check_id="hc-api"}', "0x{n}", "1x{n}")],
  failure="Route 53 health check failing", impact="DNS failover may route merchants to a wrong or no endpoint",
  sym="A Route 53 health check has been unhealthy for 3 minutes.",
  diag=["Identify the endpoint of the health check in the Terraform output.", "Compare with the blackbox probes of the same target from the three points.", "Check the health check regions in the CloudWatch metric `HealthCheckPercentageHealthy`."],
  act=["If the endpoint is healthy, fix the health check path or its security group rule in Terraform.", "If the endpoint is down, follow `region-down` or `global-accelerator-endpoint-unhealthy`.", "Do not disable the health check to silence the alert."],
  esc="Escalate to the commander if DNS failover has already moved traffic.")

a(layer=L, group="certificates", name="PspMtlsCertExpiring30d", sev="warning", team="platform", svc="egress", comp="psp-mtls", dash="edge",
  expr='min by (name) (certmanager_certificate_expiration_timestamp_seconds{name=~"psp-mtls-.*"}) - time() < 30 * 86400', f="10m",
  sum="A PSP mTLS certificate expires in less than 30 days",
  series=[('certmanager_certificate_expiration_timestamp_seconds{name="psp-mtls-acme"}', "864000x{n}", "5184000x{n}")],
  labels={"name": "psp-mtls-acme"},
  failure="PSP mTLS certificate about to expire", impact="calls to that PSP are rejected after expiry",
  sym="The mTLS certificate we present to a PSP expires within 30 days.",
  diag=["Check the cert-manager `Certificate` for the PSP and its issuer.", "Check whether the PSP must register the new certificate first."],
  act=["Request the renewal; if the PSP needs a registration, open the ticket with the PSP contact from the connector record.", "Roll the secret through Vault and verify with a test call from stage."],
  esc="Raise to platform on-call when less than 7 days remain.")

a(layer=L, group="edge", name="WafBlockedRequestsHigh", sev="warning", team="security", svc="edge", comp="waf", dash="edge",
  expr="sum by (web_acl) (rate(aws_wafv2_blocked_requests_sum[5m])) > 100", f="10m",
  sum="WAF blocks more than 100 requests per second",
  series=[('aws_wafv2_blocked_requests_sum{web_acl="payments-api"}', "0+7200x{n}", "0+0x{n}")],
  failure="WAF rule firing at a high rate", impact="an attack in progress or a rule that blocks legitimate merchants",
  sym="The WAF has been blocking over 100 requests per second for 10 minutes.",
  diag=["Check the top rules and source ASNs in the WAF logs (OpenSearch dashboard).", "Check the authorization rate: a drop with high blocks suggests false positives."],
  act=["If it is an attack, add a rate-based rule through Terraform.", "If a rule blocks legitimate merchants, switch it to count mode through a PR."],
  esc="Security on-call is informed in working hours; escalate to page if the authorization rate drops.")

a(layer=L, group="edge", name="NetworkFirewallDropsHigh", sev="warning", team="platform", svc="egress", comp="network-firewall", dash="edge",
  expr="sum by (firewall) (rate(aws_networkfirewall_dropped_packets_sum[5m])) > 1000", f="10m",
  sum="Network Firewall drops more than 1000 packets per second",
  series=[('aws_networkfirewall_dropped_packets_sum{firewall="egress-prod"}', "0+90000x{n}", "0+0x{n}")],
  failure="Network Firewall dropping traffic", impact="legitimate egress to a PSP may be blocked by a rule or domain list",
  sym="The egress firewall drops over 1000 packets per second for 10 minutes.",
  diag=["Read the drop reasons in the firewall alert log for the top destinations.", "Compare destinations with the PSP domain allow list in the policy repository."],
  act=["Add a missing PSP domain through a PR to the firewall policy.", "If the drops are an exfiltration attempt, hand over to security."],
  esc="Platform ticket; escalate to security if the destinations are unknown.")

a(layer=L, group="edge", name="CloudFront5xxHigh", sev="warning", team="platform", svc="edge", comp="cloudfront", dash="edge",
  expr="max by (distribution) (aws_cloudfront_5xx_error_rate_average) > 5", f="5m",
  sum="CloudFront 5xx error rate above 5%",
  series=[('aws_cloudfront_5xx_error_rate_average{distribution="control-center"}', "9x{n}", "0.5x{n}")],
  failure="CloudFront returns 5xx", impact="the merchant panel or static assets are unavailable",
  sym="More than 5% of responses of a CloudFront distribution are 5xx.",
  diag=["Check the origin health and the origin response time.", "Check recent changes of the distribution in the Terraform plan history."],
  act=["Fix the origin or roll back the last origin change.", "Invalidate the cache only if stale error responses are cached."],
  esc="Ticket to platform; the control-center is outside the CDE and outside the payment path.")

gap(L, "dns-resolver-failures", "route53-resolver", "Route 53 Resolver query failures inside the VPC", "services fail to resolve PSP and AWS endpoints", "warning", "no resolver metric exporter yet")
gap(L, "tgw-attachment-down", "transit-gateway", "Transit Gateway attachment down", "cells lose the path to the locker VPC", "critical", "TGW attachment state metric is not in YACE config yet")
