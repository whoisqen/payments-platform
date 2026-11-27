# locker-endpoint

Internal path from the cell clusters to the locker cluster of one environment and region (same VPC).
Internal NLB (TCP `port`, cross-zone, own security group: in from the cell node groups only, out to the locker pod group only), an IP target group,
private zone `locker.<cluster_domain>` with alias `<service>.<namespace>.svc.locker.<cluster_domain>`, the host the router builds from `global.hyperswitch.locker`.
The aws-load-balancer-controller of the locker cluster (`kube-system/aws-load-balancer-controller`, Pod Identity) only registers locker pod IPs through a TargetGroupBinding.
Test: `terraform init -backend=false && terraform test`.
