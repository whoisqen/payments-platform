# dns-routing

Route 53 failover CNAME records for the public API name: the primary endpoint (`primary_key`, the working region) serves all traffic while its health check passes; the standby record is answered only when it fails.
Each endpoint has an HTTPS health check on its ingress name (`/health/ready`, the readiness path the router serves); the standby is checked too, so a dead standby is never returned while the primary is healthy.
Test: `terraform init -backend=false && terraform test`.
