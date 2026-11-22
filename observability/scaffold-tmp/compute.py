from common import a, gap

L = "compute"

a(layer=L, group="workloads", name="CrashLoopBackOff", sev="critical", team="platform", svc="kubernetes", comp="pods", dash="kubernetes",
  expr='max by (namespace, pod, node) (kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff",namespace=~"payments-.*"} * on (namespace, pod) group_left (node) kube_pod_info) == 1', f="5m",
  sum="A payments pod is in CrashLoopBackOff",
  series=[('kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff",namespace="payments-cell-1",pod="router-7c9"}', "1x{n}", "0x{n}"), ('kube_pod_info{namespace="payments-cell-1",pod="router-7c9",node="ip-10-0-1-11"}', "1x{n}", "1x{n}")],
  labels={"namespace": "payments-cell-1", "pod": "router-7c9", "node": "ip-10-0-1-11"},
  failure="pod crash loop in a payments namespace", impact="reduced capacity of router, locker, drainer or scheduler; a cell can lose its drainer",
  sym="A container of a payments namespace has been in CrashLoopBackOff for 5 minutes.",
  diag=["Read the last termination reason and exit code with `kubectl describe` through the diagnostic document.", "Check the rollout that started it: ArgoCD history and the digest of the image.", "Check dependencies in the logs: MemoryDB, Aurora, Vault, locker."],
  act=["If a rollout caused it, roll back the application in ArgoCD (step `rollback-app`).", "If the cause is a dependency, follow the alert of that dependency instead.", "If the pod is the drainer, check the Redis stream length at once: write-behind stops without it."],
  esc="Escalate to the service owner (payments-core) when the cause is application code.")

a(layer=L, group="nodes", name="KarpenterCannotLaunchNodes", sev="critical", team="platform", svc="kubernetes", comp="karpenter", dash="kubernetes",
  expr='sum(increase(karpenter_cloudprovider_errors_total{method="Create"}[15m])) > 5', f="10m",
  sum="Karpenter cannot create nodes",
  series=[('karpenter_cloudprovider_errors_total{method="Create"}', "0+2x{n}", "0+0x{n}")], labels={},
  failure="Karpenter fails to launch nodes", impact="no scale-out, pending pods; during a switch the cells cannot be created (plan B of D7)",
  sym="Karpenter node creation calls keep failing: capacity, quota or an instance family problem.",
  diag=["Read `NodeClaim` conditions and the Karpenter log for `InsufficientInstanceCapacity` or quota errors.", "Check the NodePool requirements: instance families r7g, r6g, m7g, r7i, r6i across the three AZs.", "Check EC2 service quotas for the vCPU classes in use."],
  act=["Widen the NodePool instance families or AZs through a PR (step `widen-nodepool`).", "Ask for a quota increase through the Terraform quota module.", "During a switch this is the trigger of plan B: after 10 minutes without capacity the runbook starts compute in us-east-2."],
  esc="Escalate to the commander when it occurs during a switch or a Black Friday peak.")

a(layer=L, group="nodes", name="NodeNotReady", sev="warning", team="platform", svc="kubernetes", comp="nodes", dash="kubernetes",
  expr='kube_node_status_condition{condition="Ready",status="true"} == 0', f="5m",
  sum="A node is NotReady",
  series=[('kube_node_status_condition{condition="Ready",status="true",node="ip-10-0-1-11"}', "0x{n}", "1x{n}")],
  failure="node NotReady", impact="pods are rescheduled; capacity drops until Karpenter replaces the node",
  sym="A node has been NotReady for 5 minutes.",
  diag=["Check the node events and the kubelet condition (memory, disk, PID pressure).", "Check whether Karpenter already replaced it."],
  act=["Drain and terminate the node through Karpenter (step `replace-node`).", "If several nodes of one AZ fail, treat it as an AZ event and page the platform on-call."],
  esc="Ticket to platform; the AZ loss case is paged by the zone dashboard review.")

a(layer=L, group="workloads", name="PodOOMKilled", sev="warning", team="payments-core", svc="kubernetes", comp="pods", dash="kubernetes",
  expr='max by (namespace, pod, container) (kube_pod_container_status_last_terminated_reason{reason="OOMKilled"}) == 1 and on (namespace, pod, container) increase(kube_pod_container_status_restarts_total[10m]) > 0', f="1m",
  sum="A container was OOMKilled and restarted",
  series=[('kube_pod_container_status_last_terminated_reason{reason="OOMKilled",namespace="payments-cell-1",pod="router-7c9",container="router"}', "1x{n}", "0x{n}"),
          ('kube_pod_container_status_restarts_total{namespace="payments-cell-1",pod="router-7c9",container="router"}', "0+1x{n}", "0+0x{n}")],
  labels={"namespace": "payments-cell-1", "pod": "router-7c9", "container": "router"},
  failure="container killed for memory", impact="in-flight requests are lost and retried by the caller; repeated kills reduce capacity",
  sym="A container exceeded its memory limit and was killed within the last 10 minutes.",
  diag=["Compare memory working set with the limit over the last day on the service dashboard.", "Check for a leak after a new version: compare with the previous digest."],
  act=["Raise the limit through the chart values if the growth is legitimate.", "Roll back if a new version leaks memory."],
  esc="Ticket to the service owner.")

a(layer=L, group="workloads", name="PodsPendingTooLong", sev="warning", team="platform", svc="kubernetes", comp="scheduling", dash="kubernetes",
  expr='sum by (namespace) (kube_pod_status_phase{phase="Pending"}) > 0', f="15m",
  sum="Pods stay Pending for 15 minutes",
  series=[('kube_pod_status_phase{phase="Pending",namespace="payments-cell-1",pod="router-7c9"}', "1x{n}", "0x{n}")],
  labels={"namespace": "payments-cell-1"},
  failure="pods cannot be scheduled", impact="missing replicas; autoscaling does not take effect",
  sym="At least one pod has been Pending for 15 minutes.",
  diag=["Read the scheduling events: insufficient resources, taints, topology spread, PVC.", "Check Karpenter `NodeClaim` status."],
  act=["Fix the resource request or the topology constraint through a PR.", "If nodes cannot be created, see `karpenter-cannot-launch-nodes`."],
  esc="Ticket to platform; escalates to the page when Karpenter alert fires.")

a(layer=L, group="workloads", name="HpaAtMaxReplicas", sev="warning", team="payments-core", svc="kubernetes", comp="hpa", dash="kubernetes",
  expr="kube_horizontalpodautoscaler_status_current_replicas == kube_horizontalpodautoscaler_spec_max_replicas", f="10m",
  sum="HPA stays at its maximum replicas for 10 minutes",
  series=[('kube_horizontalpodautoscaler_status_current_replicas{namespace="payments-cell-1",horizontalpodautoscaler="router"}', "24x{n}", "10x{n}"),
          ('kube_horizontalpodautoscaler_spec_max_replicas{namespace="payments-cell-1",horizontalpodautoscaler="router"}', "24x{n}", "24x{n}")],
  failure="autoscaler at its ceiling", impact="no headroom for the next load increase",
  sym="The autoscaler has no room to add replicas.",
  diag=["Check the load against the capacity model of section 8 on the cells dashboard.", "Check whether a retry storm or a slow dependency inflates the load."],
  act=["Raise `maxReplicas` through the chart values if the load is real.", "Open a capacity task if it repeats."],
  esc="Ticket to payments-core; page only if the SLO burn alerts fire.")

a(layer=L, group="nodes", name="SubnetFreeIpsLow", sev="warning", team="platform", svc="kubernetes", comp="vpc-cni", dash="kubernetes",
  expr="min by (subnet_id) (subnet_free_ip_ratio) < 0.2", f="10m",
  sum="A subnet has less than 20% free IP addresses",
  series=[('subnet_free_ip_ratio{subnet_id="subnet-0a1"}', "0.1x{n}", "0.6x{n}")],
  failure="subnet IP exhaustion", impact="new pods cannot get an address",
  sym="Less than 20% of the addresses of a pod subnet are free.",
  diag=["Check the IPs per node and the VPC CNI prefix delegation setting.", "List the pods per subnet from the diagnostic report."],
  act=["Add a secondary CIDR subnet through Terraform.", "Enable prefix delegation for the node pool if it is off."],
  esc="Ticket to platform; urgent when below 5%.")

a(layer=L, group="nodes", name="NodeImageStale", sev="warning", team="platform", svc="kubernetes", comp="node-image", dash="kubernetes",
  expr="max by (nodepool) (node_os_image_age_seconds) > 30 * 86400", f="15m",
  sum="Nodes run an OS image older than 30 days",
  series=[('node_os_image_age_seconds{nodepool="payments"}', "3000000x{n}", "86400x{n}")],
  failure="stale node image", impact="unpatched node OS in the CDE; PCI DSS 6.3.3 patch window",
  sym="A node pool runs a Bottlerocket image older than 30 days.",
  diag=["Check the Karpenter drift and the AMI alias of the NodeClass.", "Check whether disruption budgets block the rotation."],
  act=["Start the node rotation through Karpenter drift (step `rotate-nodes`).", "Relax the disruption budget for a window if it blocks the rotation."],
  esc="Ticket to platform; the security team is informed when older than 45 days.")

a(layer=L, group="nodes", name="NodeClockDrift", sev="warning", team="platform", svc="kubernetes", comp="time-sync", dash="kubernetes",
  expr="max by (node) (abs(node_timex_offset_seconds)) > 0.1", f="5m",
  sum="Node clock drifts more than 100 ms",
  series=[('node_timex_offset_seconds{node="ip-10-0-1-11"}', "0.4x{n}", "0.001x{n}")],
  failure="clock drift", impact="idempotency windows, token expiry and log ordering are affected; PCI DSS 10.6",
  sym="The clock offset of a node exceeds 100 ms.",
  diag=["Check chrony status and the Amazon Time Sync Service reachability from the node."],
  act=["Replace the node through Karpenter; do not step the clock by hand."],
  esc="Ticket to platform.")

gap(L, "az-node-loss", "nodes", "More than 30% of the nodes of one AZ are NotReady", "AZ loss: capacity drop and cell degradation", "critical", "needs the zone label joined to node conditions")
gap(L, "node-disk-pressure", "nodes", "Node ephemeral disk pressure", "evictions of pods", "warning", "alert pending the node-exporter filesystem allowlist")
