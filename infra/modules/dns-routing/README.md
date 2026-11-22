# dns-routing

Latency-based Route 53 CNAME records for the public API name, one per regional ingress (`endpoints`).
Each record has an HTTPS health check on its ingress name (`/health/deep`); Route 53 drops an unhealthy region from the answer, which is the failover.
Writes are not routed here: the standby forwards them to the working region at application level.
Test: `terraform init -backend=false && terraform test`.
