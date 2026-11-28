# kind

The platform on a local kind cluster, the same way on a laptop and in the commit stage of `images.yml`.

| File | Purpose |
|---|---|
| `cluster.yaml` | cluster `pay-local`: one node, `kindest/node:v1.36.4` by digest (Kubernetes 1.36, as production), zone label for the zone spread of the pods; host `127.0.0.1` ports 8443 (API edge), 8444 (panel) and 8300 (Grafana) map to NodePorts 30443, 30444 and 30300 |
| `prereqs.sh` | tool versions, free memory (`MemAvailable`, capped by the Docker VM) and free disk under the Docker root; prints every gap |
| `up.sh` | creates or reuses the cluster, provides the images, `helmfile -f deploy/local/helmfile.yaml -e <demo\|ci> apply --wait`, prints the URLs |
| `down.sh`, `status.sh`, `logs.sh`, `demo.sh` | delete the cluster; nodes, releases, pods and edge health; service logs or `--export DIR`; `tests/integration` through the edge |
| `lib.sh` | shared settings; `kubectl` and `helmfile` always run with the `kind-pay-local` context |

Every script takes `--dry-run` and checks the current state first: an existing cluster is reused, a locally built image whose inputs did not change is not rebuilt, `helmfile apply` changes only what differs.

## Use

```sh
make bootstrap          # pinned kind, kubectl, helm, helmfile (mise.toml) and the helm-diff plugin
make prereqs
make up                 # ghcr.io/<owner>/<repo>/<service>:<latest v* tag>, pulled by the nodes by digest
make up VERSION=v1.4.0  # a given release
make up BUILD=1         # build from this checkout with docker buildx and load into the nodes
make status
make demo               # merchant, API key, dummy connector and a payment through https://api.payments.localhost:8443 with `x-payments-cell: cell-0`
make logs SERVICE=router
make logs EXPORT=kind-logs
make down
```

`DRY_RUN=1` prints every command instead of running it; `LOCAL_ENV=ci` installs the CI environment.

Settings (environment): `KIND_CLUSTER` (`pay-local`), `EDGE_URL` (`https://api.payments.localhost:8443`), `INTEGRATION_CELL` (`cell-0`), `GHCR_REPO` (from the `origin` remote), `LOCAL_REPO` (`pay.local`, names of locally built images), `LOCAL_CA_FILE` or the Secret `LOCAL_CA_NAMESPACE/LOCAL_CA_SECRET` (`istio-system/pay-local-ca`, key `ca.crt`) for the edge certificate, `ADMIN_KEY_SECRET` and `ADMIN_KEY_FIELD` (`router-vault`, `ROUTER__SECRETS__ADMIN_API_KEY` in `LOCAL_NAMESPACE`, default `payments`) or `INTEGRATION_ADMIN_API_KEY` for the demo.

Released images come from `tag.yml`: every `v*` release publishes each service to GitHub Packages as a signed amd64 and arm64 index. The nodes pull without credentials, so the packages are public.

## Prerequisites

| | released images (`make up`) | local build (`make up BUILD=1`) |
|---|---|---|
| Tools | Docker 24+, kind 0.33+, kubectl 1.36+, helm 3.14+, helm-diff 3.9+, helmfile 1.0+ | the same plus `docker buildx` |
| Free memory | 8 GiB | 12 GiB (one Rust release build at a time needs up to 10 GiB) |
| Free disk under the Docker root | 20 GiB | 60 GiB (build cache of four Rust services) |
| Download | node image 1.34 GB once, plus the service images | node image 1.34 GB once, plus the base images of the builds |

Override the thresholds with `MIN_RAM_GIB` and `MIN_DISK_GIB`. On macOS give the Docker Desktop VM at least the memory above.

## Measured

2026-11-26, Linux x86_64, 8 CPU, 15.5 GiB RAM, Docker 29.9.2, kind v0.33.0, `cluster.yaml` as committed:

| What | Value |
|---|---|
| `prereqs.sh` | docker, kubectl, helm present; kind, helmfile, helm-diff missing before `make bootstrap`; 9 GiB memory available, 68 GiB free under `/data/docker` |
| `kind create cluster` first run (pulls the node image) | 6 min 41 s |
| idle cluster, `docker stats` after 3 minutes | control plane 552 MiB, worker 118 MiB, 670 MiB in total; 11 system pods |
| port mapping | `30443/tcp -> 127.0.0.1:8443` |

Memory of the full stack, from the requests and limits of every release of `deploy/local` (the kind control plane included):

| Environment | Requests | Limits |
|---|---|---|
| `ci` (`LOCAL_ENV=ci`, no monitoring) | about 3.2 GiB | about 6 GiB |
| `demo` (default, with monitoring) | about 3.9 GiB | about 8 GiB |

The 8 GiB of free memory in the prerequisites covers the `demo` limits; the cell (router, drainer, scheduler) takes the largest share, 0.6 GiB requested and 1.75 GiB at its limits.
