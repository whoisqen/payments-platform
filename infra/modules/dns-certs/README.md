# dns-certs

Public Route 53 zone (`zone_name`), CAA records (ACM and Let's Encrypt only), optional DNSSEC (`enable_dnssec`) with a KMS key-signing key,
and ACM certificates (EC P-256) validated through DNS records in the same zone.
The apex and its wildcard share one validation record (`allow_overwrite`).
Certificates for CloudFront or Global Accelerator edges must be created with a us-east-1 provider; ALB and NLB
certificates use the region of the load balancer. Failover records and health checks belong to the live configuration.
Test: `terraform init -backend=false && terraform test`.
