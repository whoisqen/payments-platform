# global-accelerator

Accelerator `pay-<env>-glob-edge` with a TCP listener (443) and one endpoint group per region.
Only the writing region (eu-central-1) is `active`: weight 128 and traffic dial 100; recovery groups (us-east-1,
us-east-2) are prepared with weight 0 and dial 0, and a validation rejects two active groups.
The switch runbook flips `active` for one group; endpoints are NLB or ALB ARNs and are empty while no compute exists.
Global Accelerator is served from us-west-2: run the module with a provider for that region.
Test: `terraform init -backend=false && terraform test`.
