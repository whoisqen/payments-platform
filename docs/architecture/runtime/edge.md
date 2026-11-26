# Edge with Gateway API

## What it is

Every entry point of the platform is a Kubernetes Gateway API `Gateway` served by Istio. There are three entries:

| Entry | Who calls it | Path |
|---|---|---|
| Payments API `api.<zone>` | Merchant servers, PSP webhooks | Route 53 failover record -> regional NLB -> Gateway `payments-edge` -> router of the cell |
| Panel and SDK | Browsers | CloudFront with AWS WAF -> VPC origin -> internal NLB -> Gateway `panel` -> control center |
| Admin tools `*.payments.internal` | Platform staff on the internal network | Private Route 53 zone -> internal NLB -> admin Gateway -> oauth2-proxy or the tool's own Okta sign-in |

## Why

Gateway API is the standard, role-split model for traffic entry; the repository has no `Ingress` objects and Kyverno rejects them. Server-to-server traffic needs no CDN, so the payments API has no CloudFront; browsers do, so the panel and SDK get CloudFront and WAF.

## How it works

### Payments API

- Route 53 (`infra/modules/dns-routing`) holds a failover CNAME for `api.<zone>`. Frankfurt is primary and serves all traffic while its HTTPS health check on `/health/deep` passes. The us-east-1 standby is checked too and is answered only when Frankfurt fails.
- `edge-accelerator` keeps the static anycast addresses of Global Accelerator with one active endpoint group, the working region.
- The `payments-edge` chart creates the Gateway (class `istio`), its TLS certificate from cert-manager, an HTTPRoute per cell and the EnvoyFilter with the Lua filter, the rate limits and the overload manager. Istio scales the proxy from 3 to 12 pods on CPU.
- The first filter of the proxy (`payments-edge.header-trust`) removes client-supplied `x-payments-rate-key` and `x-payments-class` and sets the rate key from the caller's credential (see [rate limiting](rate-limiting.md)).
- One HTTPRoute per cell matches the `x-payments-cell` header of the request. The Lua filter rejects a request with 503 when that header is missing or names an unknown cell, assigns the request class by path and method, and adds `Retry-After` to every 429.
- Requests to the router use mTLS inside the mesh; the router's AuthorizationPolicy admits the edge proxy identity.
- The server-to-server API cannot take AWS WAF; it is protected by the [rate limits](rate-limiting.md).

### Panel and SDK

- `infra/modules/panel-edge` creates one CloudFront distribution per entry (`panel`, `sdk`) with HTTP/2 and HTTP/3, TLS 1.2 or newer, HSTS and a VPC origin. The origin NLB is internal and its security group admits only the CloudFront VPC origin, so WAF cannot be bypassed.
- `infra/modules/waf-edge` attaches AWS managed rules (Core, Known Bad Inputs, SQLi, IP reputation) and rate rules per IP, per API key and per merchant; logs redact authorization, cookie and API key headers.

### Admin entry

- `infra/modules/admin-edge` creates the private zone `payments.internal` (resolvable only inside the platform VPCs), a wildcard record to the internal NLB and an AWS Private CA for the certificates.
- `deploy/platform/admin-gateway` holds the Gateway, the routes and oauth2-proxy. Argo CD, Vault, Grafana and Sentry sign in with Okta directly; Alertmanager, VictoriaMetrics and Prometheus sit behind oauth2-proxy.
- Okta (`infra/modules/okta-sso`) requires two factors on every sign-in, a phishing-resistant factor for administrators and re-authentication every 2 hours for them.

## Where in the repo

| Path | What |
|---|---|
| `deploy/charts/payments-edge/` | Payments Gateway, routes, Lua, limits, overload manager |
| `deploy/envs/<env>/<region>/edge/values.yaml` | Hosts and cells per region |
| `deploy/platform/istio`, `deploy/platform/gateway-api-crds`, `cert-manager`, `aws-load-balancer-controller` | Mesh and Gateway plumbing |
| `deploy/platform/admin-gateway` | Admin entry |
| `infra/modules/dns-routing`, `dns-certs`, `global-accelerator`, `panel-edge`, `waf-edge`, `admin-edge`, `okta-sso` | AWS side |
| `docs/runbooks/network/` | Edge runbooks |
