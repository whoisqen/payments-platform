# deploy/local

The platform on one kind node. It runs the same charts as the cloud environments, with the switches gated by `global.localCluster: true`. CI uses it as the ephemeral environment, and it also serves as the local demo.

```sh
kind create cluster --config scripts/kind/cluster.yaml          # context kind-pay-local
helmfile -f deploy/local/helmfile.yaml -e <demo|ci> apply --wait \
  --state-values-set images.router.repository=pay.local/router,images.router.tag=<tag> ...
```

## Images

- Pass state values `images.<service>.repository` together with `.tag` (images built and loaded locally) or `.digest` (released images).
- Services: `router`, `drainer`, `scheduler`, `locker`, `control-center` and `smoke`, plus the optional `migrator`.
- The part of `repository` before the last slash becomes `global.registry` of the chart. All cell images must share it.
- A bare name falls back to the state value `registry`, which defaults to `pay.local`.
- Tags are accepted only because of `global.localCluster`; every other environment rejects them.
- `smoke` renders nothing until it has a tag or a digest.
- With a `migrator` image, the migrations chart Job of `cell-0` applies the Hyperswitch schema. It runs with the snapshot step off and reads its password from Secret `payments/migrator-db`.
- Without a `migrator` image, the `schema` hook Job of `local-data` applies the vendored migrations with `docker/compose/migrate.sh`, as the commit stage does.

## Environments

| | demo | ci |
|---|---|---|
| Prometheus, Grafana and the repository dashboards | yes | no |
| control-center panel Gateway | yes | no |
| PostgreSQL storage | PVC 2Gi | emptyDir |
| ratelimit service | `--state-values-set ratelimit.enabled=true` | no |

## Namespaces

| Namespace | Releases |
|---|---|
| `kube-system` | `gateway-api-crds`, `namespaces` |
| `istio-system` | `istio-base`, `istiod`, `local-access` (CA, issuer, NodePorts) |
| `cert-manager` | `cert-manager` |
| `external-secrets` | `external-secrets`, `external-secrets-config` (ClusterSecretStore `vault`) |
| `vault` | `vault-dev` |
| `payments-data` | `local-data`: `postgres:5432`, `redis:6379` and the `schema` Job |
| `mock-psp` | `mock-psp` (`mock-psp:8089`) |
| `payments` (sidecars) | `payments-locker`, `cell-0` (payments-cell) and `smoke` |
| `payments-edge` | `payments-edge`: the Gateway `payments-edge`, with proxies created by Istio |
| `control-center` (sidecars) | `control-center`, and the Gateway `panel` in demo |
| `monitoring` (demo) | `kube-prometheus-stack`, `dashboards` |
| `ratelimit` (optional) | `ratelimit` |

Pods carry the label `app.kubernetes.io/name=<service>`, where the service is `router`, `drainer`, `scheduler`, `locker` or `control-center`.

## Reachable from the host

kind maps these node ports to `127.0.0.1` (see `scripts/kind/cluster.yaml`):

| Host | Node port | What |
|---|---|---|
| `https://api.payments.localhost:8443` | 30443 | Edge Gateway (Gateway API on Istio). Send `x-payments-cell: cell-0`; without it the edge answers 503. |
| `https://panel.payments.localhost:8444` | 30444 | control-center panel (demo) |
| `http://localhost:8300` | 30300 | Grafana (demo); the login is in Secret `monitoring/grafana-admin` |

- The TLS chain ends in the cluster CA in Secret `istio-system/pay-local-ca`, key `ca.crt`.
- Example: `curl --cacert ca.crt -H 'x-payments-cell: cell-0' https://api.payments.localhost:8443/health`. `*.localhost` resolves to loopback in curl and in browsers.
- Use port-forward for anything else, for example `svc/prometheus-operated` in `monitoring` or `svc/mock-psp` in `mock-psp`.

## Secrets

The secrets path is the same as in production: Vault, then the ClusterSecretStore `vault`, then one ExternalSecret per service.

- Vault runs in dev mode. A seed container in the same pod generates every key once and keeps it in Secret `vault/vault-seed-material`. That covers the Hyperswitch keys, the router and locker RSA pairs, and the PostgreSQL and Redis passwords.
- The seed writes the keys to the KV paths the charts read: `dev/cell-0/...`, `dev/locker/...` and `dev/local/...`.
- The seed also configures Kubernetes auth for External Secrets. If Vault restarts, the seed writes the same values again.
- The router admin key is in Secret `payments/router-vault`, field `ROUTER__SECRETS__ADMIN_API_KEY`.
- PostgreSQL roles and Redis ACL users are created from the same Vault values. Each service connects as its own user: `hs_app`, `locker_app` and `cell-0-<service>`.
- Nothing secret is stored in git.

## Memory

Requests and limits are set on every container. The figures are requests, with limits in brackets.

| Component | ci | demo |
|---|---|---|
| kind control plane (apiserver, etcd, controllers, CoreDNS, kindnet) | ~1.1 GiB (no limit) | same |
| cell-0: router 256 Mi, drainer 96 Mi, scheduler 2 × 128 Mi | 608 Mi (1.75 GiB) | same |
| payments-locker | 96 Mi (256 Mi) | same |
| control-center | 64 Mi (192 Mi) | same |
| Istio sidecars, 6 × 40 Mi, and edge proxies, 2 × 40 Mi; panel proxy in demo | 320 Mi (1.5 GiB) | 360 Mi (1.7 GiB) |
| istiod | 160 Mi (384 Mi) | same |
| cert-manager, 3 pods | 120 Mi (320 Mi) | same |
| external-secrets, 3 pods | 144 Mi (384 Mi) | same |
| vault-dev, Vault and seed | 144 Mi (384 Mi) | same |
| local-data: PostgreSQL 192 Mi, Redis 48 Mi | 240 Mi (512 Mi) | same |
| mock-psp | 48 Mi (128 Mi) | same |
| smoke Job, when the image is set | 128 Mi (256 Mi) | same |
| Prometheus, Grafana, operator, kube-state-metrics | - | 640 Mi (1.45 GiB) |
| ratelimit, 3 pods, opt-in | - | 96 Mi (384 Mi) |
| **Total requests** | **~3.2 GiB** | **~3.9 GiB** (+0.1 GiB with ratelimit) |

- Idle use is close to the requests: about 3.5 GiB in ci and 4.5 GiB in demo.
- The limits bound the worst case at about 6 GiB for ci and 8 GiB for demo.

## Local differences from dev

All of them are gated by `global.localCluster`:

- image tags;
- `kms.enabled: false`, with `no_encryption` for router, scheduler, drainer and the locker;
- PostgreSQL `sslmode=disable` and Redis without TLS;
- no locker SecurityGroupPolicy;
- `Deployment` instead of Rollout, one replica, no HPA or PDB;
- no Karpenter node pool selector;
- no OpenTelemetry export.

The node carries `topology.kubernetes.io/zone`, because the pod template spreads pods across zones with `DoNotSchedule`.
