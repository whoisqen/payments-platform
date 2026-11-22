# karpenter

AWS side of Karpenter for one cluster: controller role (pod identity), node role with an `EC2_LINUX` access entry, SQS interruption queue with four EventBridge rules.
The `manifests` output holds an EC2NodeClass (Bottlerocket pinned, IMDSv2 hop limit 1, encrypted gp3, no public IP) and NodePools `payments`, `stateful`, `cde` (On-Demand, tainted) and `workers` (Spot allowed, tainted); `enabled_pools` selects the set per cluster. The shared-services cluster sets `["ci", "ci-prod"]` (taints `workload=ci` and `workload=ci-prod`; `ci` may use Spot, `ci-prod` is On-Demand) and cannot be mixed with the payments pools.
CRDs are not applied from Terraform: ArgoCD applies the manifests, so plan works offline and compute can be created at the switch.
Required: `region`, `account_id`, `cluster_name`, `permissions_boundary_arn`, `ebs_kms_key_arn`, `subnet_ids`, `security_group_ids`, `bottlerocket_version`, `tags`.
Test: `terraform init -backend=false && terraform test` (mock provider).
