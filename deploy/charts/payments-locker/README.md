# payments-locker

The locker (card vault) with its own migrations Job, one release per environment and region in the locker cluster.

## Cross-cluster access from the cells

The cells reach the locker through an internal NLB and a locker Gateway that terminates mutual TLS:

- Router (cell cluster) calls `http://locker.payments.svc.locker.<cluster_domain>:3001`. A ServiceEntry registers the host under `outboundTrafficPolicy: REGISTRY_ONLY`. A DestinationRule makes the sidecar originate mutual TLS with the client certificate `locker-client-tls` (`deploy/charts/router/templates/istio/locker-serviceentry.yaml`).
- `infra/modules/locker-endpoint` provides the internal NLB (TCP 3001) and the private zone with the alias of that host. The `TargetGroupBinding` `locker-gateway` registers the gateway pods in the Terraform target group. The gateway pods carry the locker pod security group, which is the only target the NLB security group allows.
- Gateway `locker` (Gateway API, Istio) uses `tls-terminate-mode: MUTUAL`. It accepts only client certificates of the mesh root. The AuthorizationPolicy `locker-gateway` then admits only the principal `payments-platform/ns/payments/sa/router`, the URI SAN of the router certificate. The gateway forwards to the locker over in-mesh mutual TLS, and the locker AuthorizationPolicy admits the gateway service account `locker-istio`.
- Certificates come from the Vault mesh PKI `pki-mesh` (`deploy/platform/vault/config`, workloads), and the root key never leaves Vault:
  - Role `router-client` signs only that URI SAN. Role `locker-gateway` signs only names under the cluster domain.
  - External Secrets `VaultDynamicSecret` generators issue the certificates with the Vault login of the router (`<cell>-router` on the auth mount of its cell) and of `locker-gateway-pki` (auth mount `kubernetes-locker`). Certificates live 72 h and are renewed every 24 h.

Why not an east-west gateway with a shared Istio root: the clusters run separate meshes, with no meshID, network or remote secrets. The locker is the only cross-cluster call, so one mutual TLS hop with its own PKI is a smaller change than multi-primary Istio.
