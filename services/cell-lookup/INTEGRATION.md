# cell-lookup integration

This file lists what other areas must add so the edge picks the cell itself. The service code is in this directory; everything below lives in `deploy/`, `infra/`, `docker/` and `.github/`, and those areas own it.

## 1. Route table (infra, `infra/modules/dynamodb-global` + new live stack)

Create a second instance of `dynamodb-global`; do not change `merchant-cell-map`, because its key is `merchant_id`.

**Table**

- Name: `pay-<env>-euc1-cell-lookup`, component `cell-lookup`.
- Billing: `PAY_PER_REQUEST`.
- Encryption: KMS key `shared`.
- Replicas: the same MREC replicas as `merchant-cell-map`; only Frankfurt writes, and `deny_recovery_writes` applies.
- Stack: `infra/live/<env>/eu-central-1/cell-lookup-table/terragrunt.hcl`, a copy of `dynamodb/terragrunt.hcl` with `component = "cell-lookup"` and `hash_key = "lookup_key"`.

**Module additions** (optional, defaults keep the current table unchanged)

- `global_secondary_indexes`: a list of `{name, hash_key, projection_type}`.
- `ttl_attribute`: a string, default `null`.

**Keys and attributes**

| Attribute | Type | Role |
|---|---|---|
| `lookup_key` | S | Partition key. `h#<64 hex>` for a keyed hash of a secret or publishable key; `m#<merchant_id>` for a merchant |
| `cell` | S | `cell-0`..`cell-3`, `spare`. GSI `by-cell` partition key, projection `ALL` |
| `merchant_id` | S | Merchant that owns the item |
| `kind` | S | `api_key`, `publishable_key` or `merchant` |
| `expires_at` | N | Unix seconds, only on keys that expire. TTL attribute (`ttl_attribute = "expires_at"`) |

**Scan cost per serve pod**

- Each refresh is one full Scan: about `items x 150 B / 4 KiB / 2` read units.
- Budget it as `pods x 3600 / CELL_LOOKUP_REFRESH_SECONDS` scans per hour.
- Raise the refresh interval if the key count grows past about 100k.

## 2. IAM (infra, IRSA roles)

**`pay-<env>-euc1-cell-lookup`**

- Trust: the edge cluster OIDC provider, service account `payments-edge:cell-lookup`.
- Actions: `dynamodb:Scan`, `dynamodb:BatchGetItem`.
- Resource: the table ARN.

**`pay-<env>-euc1-<cell>-cell-lookup-sync`**, one per cell

- Trust: that cell cluster's OIDC provider, service account `payments:cell-lookup-sync`.
- Actions:
  - `dynamodb:Query` on `<table>/index/by-cell`.
  - `dynamodb:BatchGetItem` and `dynamodb:BatchWriteItem` on the table.
- Attach `deny_recovery_writes_policy_arn` of the new table to the sync roles.

Both roles reach DynamoDB through the VPC gateway endpoint and STS through the regional endpoint.

## 3. Database user (infra, Aurora bootstrap of each cell)

Create a read-only login with column grants only. The sync never sees `api_keys.name`, keys of other columns or any other table.

```sql
CREATE ROLE cell_lookup_ro LOGIN PASSWORD '<from Vault>';
GRANT SELECT (hashed_api_key, merchant_id, expires_at) ON api_keys TO cell_lookup_ro;
GRANT SELECT (merchant_id, publishable_key) ON merchant_account TO cell_lookup_ro;
ALTER ROLE cell_lookup_ro SET default_transaction_read_only = on;
```

- The password is stored at Vault `secret/<env>/<cell>/cell-lookup/database`, field `password`.
- Connect through the reader endpoint of the cell's Aurora cluster.

## 4. Vault (deploy/platform/vault)

- **Sync** (cell clusters): add service `cell-lookup-sync` to `bootstrap.workloads` so it gets the role `<cell>-cell-lookup-sync` and policy `pay-<cell>-cell-lookup-sync`. The policy reads:
  - `secret/<env>/<cell>/shared/app`, field `api_keys_hash_key`, which is needed to hash publishable keys.
  - `secret/<env>/<cell>/cell-lookup/database`.
- **Serve** (edge cluster): needs `api_keys_hash_key` of every cell. KV v2 policies cannot restrict a single field, and `shared/app` also holds `master_enc_key`, `jwt_secret` and `admin_api_key`.
  - Copy the field to `secret/<env>/<cell>/cell-lookup/hash`, field `api_keys_hash_key`, whenever it is written or rotated.
  - Grant the edge role `pay-edge-cell-lookup` read on `secret/<env>/+/cell-lookup/hash` only.
  - If the owner keeps `shared/app` as the source, record the wider read in the threat model.

## 5. Helm, serve (new chart `deploy/charts/cell-lookup`, edge cluster, namespace `payments-edge`)

Deploy it from the `payments-edge` ApplicationSet as a second source, or as its own ApplicationSet over `deploy/envs/*/*/edge`.

**Workload**

- `Deployment`, 3 replicas, spread across zones.
- `PodDisruptionBudget` `minAvailable: 2`.
- HPA on CPU at 60 %, max 12.
- Image `cell-lookup` by digest from `deploy/envs/<env>/images.yaml`.
- `args: ["serve"]`.
- Runs as user `10001`, read-only root filesystem, no capabilities.

**Ports and probes**

- Container ports: `authz` 9191, `admin` 9090.
- `Service` `cell-lookup` exposes both. Name the ports `http-authz` and `http-admin` for Istio protocol selection.
- Probes on `admin`: liveness `GET /healthz`, readiness `GET /readyz`, startup `GET /readyz` with `failureThreshold: 30`, `periodSeconds: 2`.

**Environment**

| Variable | Value |
|---|---|
| `CELL_LOOKUP_TABLE` | `pay-<env>-euc1-cell-lookup` |
| `CELL_LOOKUP_CELLS` | The cells of `routing.cells` in the edge values, comma-joined |
| `AWS_REGION` | `eu-central-1` |
| `RUST_LOG` | `info` |
| `CELL_LOOKUP_REFRESH_SECONDS` | `30` |
| `CELL_LOOKUP_MISS_CONCURRENCY` | `16` |

**Secrets**

- `ExternalSecret` from store `vault`.
- One variable per cell: `CELL_LOOKUP_HASH_KEY_CELL_0` from `<env>/cell-0/cell-lookup/hash` property `api_keys_hash_key`, and so on. `spare` maps to `CELL_LOOKUP_HASH_KEY_SPARE`.

**Service account**

- `cell-lookup`, IRSA annotation with the role from section 2.

**Resources**

- Requests: `cpu: 100m`, `memory: 128Mi`.
- Limit: `memory: 512Mi`. The snapshot is about 300 B per item, plus the capped caches.

**Monitoring and network**

- `ServiceMonitor` on port `http-admin`, path `/metrics`, 15 s.
- `NetworkPolicy`:
  - Ingress on 9191 from the gateway proxy pods (`gateway.networking.k8s.io/gateway-name: payments-edge`).
  - Ingress on 9090 from namespace `monitoring`.
  - Egress to DNS and TCP 443.
- Istio `AuthorizationPolicy`: port 9191 admits only the edge proxy service account.

**Alerts** (observability)

- `cell_lookup_snapshot_age_seconds > 120` for 5 min.
- `rate(cell_lookup_lookups_total{result="unavailable"}[5m]) > 0`.
- p99 of `cell_lookup_lookup_duration_seconds` above 1 ms.

## 6. Helm, sync CronJob (chart `deploy/charts/payments-cell`, every cell cluster, namespace `payments`)

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: cell-lookup-sync
spec:
  schedule: "* * * * *"
  concurrencyPolicy: Forbid
  startingDeadlineSeconds: 50
  successfulJobsHistoryLimit: 1
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      backoffLimit: 0
      activeDeadlineSeconds: 240
      template:
        spec:
          serviceAccountName: cell-lookup-sync
          restartPolicy: Never
          securityContext: {runAsNonRoot: true, runAsUser: 10001, seccompProfile: {type: RuntimeDefault}}
          containers:
            - name: sync
              image: <registry>/cell-lookup@<digest>
              args: ["sync"]
              env:
                - {name: CELL_LOOKUP_CELL, value: <cell>}
                - {name: CELL_LOOKUP_TABLE, value: pay-<env>-euc1-cell-lookup}
                - {name: AWS_REGION, value: eu-central-1}
                - {name: CELL_LOOKUP_DB_ROOT_CERT, value: /etc/ssl/rds/ca.pem}
                - {name: CELL_LOOKUP_MAX_DELETE_RATIO, value: "0.2"}
              envFrom:
                - secretRef: {name: cell-lookup-sync}
              volumeMounts:
                - {name: rds-ca, mountPath: /etc/ssl/rds, readOnly: true}
              securityContext: {readOnlyRootFilesystem: true, allowPrivilegeEscalation: false, capabilities: {drop: [ALL]}}
              resources: {requests: {cpu: 50m, memory: 64Mi}, limits: {memory: 256Mi}}
          volumes:
            - name: rds-ca
              configMap: {name: <the rds CA ConfigMap platform-common already mounts>, items: [{key: ca.pem, path: ca.pem}]}
```

**Secret `cell-lookup-sync`** (an ExternalSecret)

- `CELL_LOOKUP_HASH_KEY_<CELL>` from `<env>/<cell>/shared/app` property `api_keys_hash_key`.
- `CELL_LOOKUP_DATABASE_URL`, built by an ExternalSecret template:
  `postgres://cell_lookup_ro:{{ .password }}@<reader endpoint>:5432/<db name>`.
  Do not put `sslmode` in it; the binary defaults to `verify-full`.

**Network and alert**

- `NetworkPolicy`: egress to the Aurora reader on 5432, DNS, TCP 443.
- Alert: the CronJob has had no successful Job for 10 min (`kube_cronjob_status_last_successful_time`).

## 7. Edge Envoy (`deploy/charts/payments-edge`)

**Values** (add to the schema):

```yaml
cellLookup:
  enabled: false
  host: cell-lookup.payments-edge.svc.cluster.local
  port: 9191
  timeout: 0.25s
```

**`templates/envoyfilter.yaml`, behind `cellLookup.enabled`**

Add this patch to the list **before** the cell-guard Lua patch. Each `INSERT_BEFORE router` lands after the previous ones, so the order of the list is the order of the filters: header trust, then `ext_authz`, then cell guard, then limiters.

```yaml
- applyTo: HTTP_FILTER
  match:
    context: GATEWAY
    listener:
      filterChain:
        filter:
          name: envoy.filters.network.http_connection_manager
          subFilter:
            name: envoy.filters.http.router
  patch:
    operation: INSERT_BEFORE
    value:
      name: envoy.filters.http.ext_authz
      typed_config:
        "@type": type.googleapis.com/envoy.extensions.filters.http.ext_authz.v3.ExtAuthz
        transport_api_version: V3
        failure_mode_allow: false
        status_on_error:
          code: ServiceUnavailable
        include_peer_certificate: false
        http_service:
          # no path_prefix: the service matches merchant ids in the original path
          server_uri:
            uri: http://{{ .Values.cellLookup.host }}:{{ .Values.cellLookup.port }}
            cluster: outbound|{{ .Values.cellLookup.port }}||{{ .Values.cellLookup.host }}
            timeout: {{ .Values.cellLookup.timeout }}
          authorization_request:
            allowed_headers:
              patterns:
                - exact: {{ .Values.routing.apiKeyHeader }}
                - exact: {{ .Values.routing.authHeader }}
                - exact: x-merchant-id
          authorization_response:
            allowed_upstream_headers:
              patterns:
                - exact: {{ .Values.routing.cellHeader }}
                - exact: x-merchant-id
            allowed_client_headers:
              patterns:
                - exact: content-type
                - exact: retry-after
```

**`templates/_helpers.tpl`, `payments-edge.trustLua`**

When `cellLookup.enabled`, add `routing.cellHeader` to the `strip` list. A client copy of `x-payments-cell` then never reaches `ext_authz` or the cell guard. The cell guard stays as a second check that the chosen cell is in `routing.cells`.

**CORS:** the edge has no CORS filter; the router answers CORS. Preflights (`OPTIONS` without a credential) get `200` from cell-lookup with `x-payments-cell` set to `CELL_LOOKUP_PREFLIGHT_CELL`, so they still reach a router.

**Updates in the same change**

- Update the comment on `routing.cellHeader` in `values.yaml`: the cell is set by the edge.
- Add a `helm unittest` case: the filter is present when enabled, comes before the cell-guard Lua, and `strip` contains the cell header.
- Rollout: enable in `dev`, check `cell_lookup_lookups_total{result="found"}` against the edge request rate, then `stage` and `prod`.

## 8. Dockerfile (`docker/cell-lookup/Dockerfile`, context = repository root)

```dockerfile
# rust:1.94.1-bookworm (manifest list, arm64 and amd64)
FROM rust@sha256:6ae102bdbf528294bc79ad6e1fae682f6f7c2a6e6621506ba959f9685b308a55 AS build
ARG SOURCE_DATE_EPOCH
ENV SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH} CARGO_INCREMENTAL=0 \
    RUSTFLAGS="-C strip=symbols --remap-path-prefix=/src=/build --remap-path-prefix=/usr/local/cargo=/cargo"
WORKDIR /src
COPY services/cell-lookup/Cargo.toml services/cell-lookup/Cargo.lock services/cell-lookup/rust-toolchain.toml ./
RUN mkdir src && touch src/lib.rs && echo 'fn main() {}' > src/main.rs
RUN --mount=type=cache,target=/usr/local/cargo/registry cargo fetch --locked
COPY services/cell-lookup/ ./
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    cargo build --locked --release && install -D target/release/cell-lookup /out/cell-lookup

# distroless cc-debian12 nonroot (manifest list, arm64 and amd64)
FROM gcr.io/distroless/cc-debian12@sha256:9dac0a79194e45a7da0158a9c6da57b217585af0786db3845d1f0ec1a0dd182f
ARG SOURCE_URL=unknown
ARG REVISION=unknown
ARG CREATED=unknown
LABEL org.opencontainers.image.source="${SOURCE_URL}" \
      org.opencontainers.image.revision="${REVISION}" \
      org.opencontainers.image.created="${CREATED}"
COPY --from=build --chmod=0555 /out/cell-lookup /app/cell-lookup
USER 10001:10001
STOPSIGNAL SIGTERM
EXPOSE 9191 9090
ENTRYPOINT ["/app/cell-lookup"]
```

The image needs no system libraries: TLS is rustls (ring and aws-lc-rs are linked statically), and there is no libpq or OpenSSL. A `docker/cell-lookup/Dockerfile.dockerignore` should admit only `services/cell-lookup/` without `target/`. Add the image to `docker/_common/budgets.yaml` at about 40 MB.

## 9. CI (`.github/workflows`, `tools/ci`)

**`tools/ci/image-paths.yaml`**

- Image `cell-lookup: [docker/cell-lookup/, services/cell-lookup/]`.
- Area `rust_cell_lookup: [services/cell-lookup/]`.

**Workflows**

- `tools/ci/changed_images.py` `SERVICES` and the `jq` list in `images.yml`: add `cell-lookup`.
- `ci.yml` `rust` matrix: add an entry
  `{dir: services/cell-lookup, toolchain: 1.94.1, area: area_rust_cell_lookup, clippy_blocking: true}`,
  include the area in the job `if`, and run the whole crate. It is not a workspace, so `rust_scope.py` can be skipped for it.
- `ci.yml` `changes` job: output `area_rust_cell_lookup`.
- `security.yml`: run `cargo audit` / `cargo deny` over `services/cell-lookup/Cargo.lock` as for the vendored workspaces.

## 10. Docs

- `docs/security/threat-model.md` B2: the cell is chosen at the edge from the credential, the path merchant id or the JWT claim. The client header is stripped. `ext_authz` fails closed (503).
- Known gaps, now refused at the edge:
  - `epk_` requests without a merchant in the path: `403`.
  - Admin-key calls with no merchant in the path or in `x-merchant-id` (for example `POST /accounts`, `/organization`): `403`. Route them to one designated cell, or add that cell as a path rule fallback, if they must pass the public edge.
  - `/user/*` sign-in and sign-up before a JWT exists: `404`. The dashboard needs a fixed cell or its own route.
- New-key latency: a new or rotated key works at the edge after the next sync run (one minute or less) plus at most one refresh interval. Revocation reaches the edge in the same time.
