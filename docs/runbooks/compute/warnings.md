# compute: non-paging alerts

Each section is the runbook of one ticket or Slack alert; the alert annotation links to its anchor. A ticket is handled in working hours; if the condition persists past the stated escalation, the owner raises it to the on-call.

## node-not-ready

Alert `NodeNotReady`, severity warning, owner platform-oncall, dashboard https://grafana.payments.internal/d/kubernetes.

### Symptom

A node has been NotReady for 5 minutes.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=NodeNotReady`) runs the read-only step of SSM document `pay-runbook-node-not-ready`.
2. Check the node events and the kubelet condition (memory, disk, PID pressure).
3. Check whether Karpenter already replaced it.

### Actions

1. Drain and terminate the node through Karpenter (step `replace-node`).
2. If several nodes of one AZ fail, treat it as an AZ event and page the platform on-call.

### Escalation

Ticket to platform; the AZ loss case is paged by the zone dashboard review.

### SSM document

`pay-runbook-node-not-ready`

## pod-oom-killed

Alert `PodOOMKilled`, severity warning, owner payments-core-oncall, dashboard https://grafana.payments.internal/d/kubernetes.

### Symptom

A container exceeded its memory limit and was killed within the last 10 minutes.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=PodOOMKilled`) runs the read-only step of SSM document `pay-runbook-pod-oom-killed`.
2. Compare memory working set with the limit over the last day on the service dashboard.
3. Check for a leak after a new version: compare with the previous digest.

### Actions

1. Raise the limit through the chart values if the growth is legitimate.
2. Roll back if a new version leaks memory.

### Escalation

Ticket to the service owner.

### SSM document

`pay-runbook-pod-oom-killed`

## pods-pending-too-long

Alert `PodsPendingTooLong`, severity warning, owner platform-oncall, dashboard https://grafana.payments.internal/d/kubernetes.

### Symptom

At least one pod has been Pending for 15 minutes.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=PodsPendingTooLong`) runs the read-only step of SSM document `pay-runbook-pods-pending-too-long`.
2. Read the scheduling events: insufficient resources, taints, topology spread, PVC.
3. Check Karpenter `NodeClaim` status.

### Actions

1. Fix the resource request or the topology constraint through a PR.
2. If nodes cannot be created, see `karpenter-cannot-launch-nodes`.

### Escalation

Ticket to platform; escalates to the page when Karpenter alert fires.

### SSM document

`pay-runbook-pods-pending-too-long`

## hpa-at-max-replicas

Alert `HpaAtMaxReplicas`, severity warning, owner payments-core-oncall, dashboard https://grafana.payments.internal/d/kubernetes.

### Symptom

The autoscaler has no room to add replicas.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=HpaAtMaxReplicas`) runs the read-only step of SSM document `pay-runbook-hpa-at-max-replicas`.
2. Check the load against the capacity model of section 8 on the cells dashboard.
3. Check whether a retry storm or a slow dependency inflates the load.

### Actions

1. Raise `maxReplicas` through the chart values if the load is real.
2. Open a capacity task if it repeats.

### Escalation

Ticket to payments-core; page only if the SLO burn alerts fire.

### SSM document

`pay-runbook-hpa-at-max-replicas`

## subnet-free-ips-low

Alert `SubnetFreeIpsLow`, severity warning, owner platform-oncall, dashboard https://grafana.payments.internal/d/kubernetes.

### Symptom

Less than 20% of the addresses of a pod subnet are free.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=SubnetFreeIpsLow`) runs the read-only step of SSM document `pay-runbook-subnet-free-ips-low`.
2. Check the IPs per node and the VPC CNI prefix delegation setting.
3. List the pods per subnet from the diagnostic report.

### Actions

1. Add a secondary CIDR subnet through Terraform.
2. Enable prefix delegation for the node pool if it is off.

### Escalation

Ticket to platform; urgent when below 5%.

### SSM document

`pay-runbook-subnet-free-ips-low`

## node-image-stale

Alert `NodeImageStale`, severity warning, owner platform-oncall, dashboard https://grafana.payments.internal/d/kubernetes.

### Symptom

A node pool runs a Bottlerocket image older than 30 days.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=NodeImageStale`) runs the read-only step of SSM document `pay-runbook-node-image-stale`.
2. Check the Karpenter drift and the AMI alias of the NodeClass.
3. Check whether disruption budgets block the rotation.

### Actions

1. Start the node rotation through Karpenter drift (step `rotate-nodes`).
2. Relax the disruption budget for a window if it blocks the rotation.

### Escalation

Ticket to platform; the security team is informed when older than 45 days.

### SSM document

`pay-runbook-node-image-stale`

## node-clock-drift

Alert `NodeClockDrift`, severity warning, owner platform-oncall, dashboard https://grafana.payments.internal/d/kubernetes.

### Symptom

The clock offset of a node exceeds 100 ms.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=NodeClockDrift`) runs the read-only step of SSM document `pay-runbook-node-clock-drift`.
2. Check chrony status and the Amazon Time Sync Service reachability from the node.

### Actions

1. Replace the node through Karpenter; do not step the clock by hand.

### Escalation

Ticket to platform.

### SSM document

`pay-runbook-node-clock-drift`
