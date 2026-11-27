# global-accelerator

Accelerator `pay-<env>-glob-edge` with a TCP listener (443) and one endpoint group per region.
Only the writing region (eu-central-1) is `active`: weight 128 and traffic dial 100; the standby group (us-east-1, prod)
is prepared with weight 0 and dial 0, and a validation rejects two active groups.
The switch runbook flips `active` for one group; endpoints are `endpoint_arns` plus the load balancers of the region that carry all `endpoint_lb_tags` (the edge ingress), none until they exist.
Global Accelerator is served from us-west-2: run the module with a provider for that region.
Test: `terraform init -backend=false && terraform test`.
