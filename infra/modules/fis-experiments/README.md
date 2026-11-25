# fis-experiments

AWS FIS templates for the chaos experiments of `tests/chaos/fis`, one account, blast radius at most one AZ or one cell.

- Templates: `az-loss` (network disruption of the subnets of `target_az`), `node-loss` (Karpenter `node_pool` nodes in `target_az`), `workers-spot-interruption`, `aurora-writer-failover` and `memorydb-failover` (SSM Automation document calling FailoverShard) of `target_cell`.
- With `eks_pod_actions`: `pod-loss` (pod deletion in `target_az`) and, with `psp_latency`, `psp-egress-latency` (`aws:eks:pod-network-latency` on the egress pods towards the PSP destinations). Both need an EKS access entry for `role_arn` and the service account with RBAC in the cluster. Network Firewall has no FIS action, so latency is injected at the pods; Istio delay in `tests/chaos/chaos-mesh/psp-timeout.yaml` covers the rest.
- Every template: `Hypothesis:` description, stop conditions from `stop_alarm_arns` (they must exist), targets selected by the `environment` tag (plus `cell`), log group `/fis/<name>` (KMS, 365 days), empty targets fail.
- The role may act only on resources tagged with its environment; its boundary must allow the network ACL actions of disrupt-connectivity.
- Prod: role, log group and document exist, templates only with `allow_prod = true`. Starting an experiment is a pipeline job behind `tests/chaos/lib/guard.py`.
