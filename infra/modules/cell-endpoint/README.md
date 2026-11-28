# cell-endpoint

Cross-cluster entry of one cell from the edge cluster of the same region: an internal NLB (TCP) in front of the mutual-TLS router
gateway of the cell (`deploy/charts/payments-cell`, `routerGateway`), in its own private zone `<cell>.<cluster_domain>` with the record
`router.payments.svc.<cell>.<cluster_domain>`, the host the edge builds (`deploy/charts/payments-edge`, `routing.cells`).
Only the node security group of the edge cluster reaches the load balancer, and only the load balancer reaches the cell nodes on
the gateway port. The gateway admits only the edge client certificate (Vault mesh PKI, role `edge-client`); its own certificate comes
from role `cell-gateway`. The load balancer controller of the cell cluster registers the gateway pods through a TargetGroupBinding
with the role of this module (Pod Identity, trusted by that cluster only).
Test: `terraform init -backend=false && terraform test`.
