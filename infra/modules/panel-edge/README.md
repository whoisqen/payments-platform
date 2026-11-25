# panel-edge

Public CloudFront entries of the control-center panel and the browser payment SDK (`entries`, default `panel`, `sdk`), each with the `waf-edge` ACL (`web_acl_arns`), at `<subdomain>.<zone_name>`.
- Stack runs in us-east-1 (ACM certificate per entry, DNS-validated in `zone_id`; logging v2 source). The NLB lookup alone runs in `origin_region` (provider 6 per-resource region); it finds the internal NLB that the AWS Load Balancer Controller built from the `panel` Gateway, by tag `service.k8s.aws/stack` (`nlb_stack_tag`, optional `nlb_cluster_name`).
- Two steps: `nlb_lookup_enabled = false` creates certificates, policies and the log destination; `true` adds the VPC origin (HTTPS only, TLSv1.2), distributions (HTTP/2 and 3, `TLSv1.2_2021`, SNI, IPv6, `geo_restriction`) and A/AAAA aliases.
- No shared-secret origin header: the NLB is internal, has no public path and its security group admits only the CloudFront VPC origin ENIs, so WAF cannot be bypassed.
- Behaviors: `api_paths` and the default are not cached (`max_ttl = 1` so that the cache policy can forward `Authorization`); `static_paths` use `static_ttl`. Origin request policy forwards `origin_headers` (Host required), all query strings, cookies only from `forward_cookies`. Response headers: HSTS, nosniff, referrer policy, CSP placeholder per entry, `X-Frame-Options: DENY` unless `frame_deny = false` (SDK iframe).
- Access logs (standard logging v2): CloudWatch log group with `kms_key_arn`, or S3 (`log_bucket_arn`, Parquet); `log_record_fields` exclude query string and cookies.
- Origin needs (outside this module): an internet gateway attached to the cluster VPC, an NLB security group admitting `CloudFront-VPCOrigins-Service-SG` on 443, a publicly trusted Gateway certificate for every host name.
- Test: `terraform init -backend=false && terraform test` (mock providers).
