# Istio add-on

Argo CD (`deploy/argocd/templates/addons/istio.yaml`) installs three upstream charts in order: `base` and `istiod` into `istio-system`, then `gateway` into `istio-ingress` with `values-gateway.yaml` (the `istio: ingressgateway` deployment, 3 to 12 pods).

## Old ingress gateway

The edge entry point is now Gateway `payments-edge` (Gateway API, `deploy/charts/payments-edge`). Istio creates its proxy Deployment, Service and service account `payments-edge-istio` in namespace `payments-edge`; the rate-limit `EnvoyFilter` targets that Gateway only. The `istio: ingressgateway` deployment is kept for now, and `values-gateway.yaml` stays, because:

- Nothing in the repository proves that the `payments-edge` proxy already carries production traffic. Its load balancer, DNS and certificate cut-over is an operational step outside `deploy/`; removing the old gateway before it drops the only live entry point.
- `deploy/charts/router/values.yaml` (`istio.authorizationPolicy.principals`) still lists `cluster.local/ns/istio-system/sa/istio-ingressgateway` next to the new `payments-edge-istio` principal.
- The add-on ApplicationSet still lists the `gateway` chart; with `ignoreMissingValueFiles: true`, deleting only the values file would deploy the upstream defaults instead of removing the gateway.

Nothing else in `deploy/` references the old gateway: the rate-limit NetworkPolicy and the mesh policies of `deploy/platform/ratelimit` select the new proxy only (the old gateway never called the rate-limit service).

To retire it after the cut-over: delete `values-gateway.yaml`, remove the `gateway` element from `addons/istio.yaml` (the Application prune removes the deployment), and drop the old principal from the router values.
