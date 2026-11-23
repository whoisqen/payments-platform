# dns-routing

Route 53 failover CNAME records for the public API name: the primary endpoint (`primary_key`, the working region) serves all traffic while its health check passes; the standby record is answered only when it fails.
Each endpoint has an HTTPS health check on its ingress name (`/health/deep`); the standby is checked too, so a dead standby is never returned while the primary is healthy.
Writes are not routed here: the standby forwards them to the working region at application level.
Test: `terraform init -backend=false && terraform test`.
