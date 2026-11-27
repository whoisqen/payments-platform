# waf-edge

AWS WAFv2 web ACLs for the public browser entries (control-center panel, payment SDK) behind CloudFront. The server-to-server API (Global Accelerator, NLB, Istio) cannot take a WAF; it is limited in Envoy.

- One ACL per key of `entries` (`panel`, `sdk`). AWS managed groups: Core, Known Bad Inputs, SQLi, IP reputation; Bot Control and Account Takeover Prevention only where `bot_control` / `atp` are set (ATP sees `login_path` only).
- `mode` = `count` (default) or `block`, one switch for managed groups and rate rules. Rate rules (per IP, per `api_key_header`, per `merchant_header`, stricter per IP on `auth_paths`) answer 429 with `Retry-After` = `evaluation_window_sec`.
- Log group `aws-waf-logs-<name>-<entry>` per ACL, KMS `kms_key_arn`, 30 days, redacting authorization, cookie and x-api-key. Metrics and sampled requests on.
- `scope = CLOUDFRONT` must run in us-east-1 (a precondition fails elsewhere), so the logs live there too; `REGIONAL` serves an ALB or API Gateway.
- Attach: set `web_acl_id` of the distribution to `web_acl_arns[<entry>]` (see output `association`); the module does not own distributions.

Tags: `tags` must carry team, owner, pci-scope, data-class and backup-tier.

`count_overrides` keeps single rules of a blocking managed group in count (group key -> rule names). Test: `terraform init -backend=false && terraform test` (mock providers).
