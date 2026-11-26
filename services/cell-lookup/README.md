# cell-lookup

The edge uses this service to choose the cell for each request. It reads the caller's credential, looks it up in a route table, and tells Envoy which cell to use. The client's `x-payments-cell` header is never trusted (threat model B2). One binary has two sub-commands:

- `serve`: the Envoy HTTP `ext_authz` server. It runs in the edge cluster, namespace `payments-edge`.
- `sync`: copies one cell's API keys and merchants into the route table. It runs as a CronJob in every cell.

Wiring for other areas (Envoy, Helm, CronJob, DynamoDB, Dockerfile, CI) is in [INTEGRATION.md](INTEGRATION.md).

## How a request is resolved

1. **Credential.** Credentials are read in the order the edge rate-key filter uses:
   - The `api-key` header (a secret key or a `pk_` key).
   - Otherwise `Authorization`:
     - `api-key=` / `publishable-key=` fields.
     - SDK authorization (base64, `publishable_key=`).
     - `Bearer <JWT>`. The `merchant_id` claim is used for routing only; the cell verifies the signature.
2. **Hashing.** A key is hashed with every cell's `api_keys_hash_key`, the same way Hyperswitch does it: BLAKE3 keyed hash, lower-case hex, `blake3 = "=1.8.2"`. An item counts only if its `cell` is the cell whose key produced the hash.
3. **Merchant fallback.** If there is no credential, or the credential is unknown, an ephemeral key, or a JWT, the cell is found by merchant id instead. The id comes from, in order:
   - The path: PSP webhooks, redirects, payment and payout links, `/account/{id}`.
   - The `x-merchant-id` header, which admin-key calls use.
   - The JWT claim.

   Each of these only selects that merchant's own cell.
4. **Answer.**

| Outcome | Status | Headers / code |
|---|---|---|
| Routed | `200` | `x-payments-cell`; `x-merchant-id` only if the request had none |
| Unknown or expired credential | `403` | `CL_01` |
| Nothing names a merchant | `404` | `CL_02` |
| Table unreadable and the cache cannot answer | `503` | `CL_03`, `retry-after: 1` |

A CORS preflight (`OPTIONS` with no credential) gets `200` and `CELL_LOOKUP_PREFLIGHT_CELL` (default: the first of `CELL_LOOKUP_CELLS`), since every cell's router answers it the same way.

Ephemeral keys (`epk_`) are kept only in the cell's Redis. They route only when the path names the merchant; otherwise the answer is `403`.

## Cache

- **Snapshot.** The whole table is scanned every `CELL_LOOKUP_REFRESH_SECONDS` (30) into an in-memory map. A lookup costs one BLAKE3 hash per cell plus a hash-map read. The test `cached_lookup_is_well_under_a_millisecond` bounds it at 200 µs even in a debug build.
- **Keys missing from the snapshot.** They are read from the table with `BatchGetItem`:
  - At most `CELL_LOOKUP_MISS_CONCURRENCY` (16) reads run at once; `0` turns these reads off.
  - Hits are kept for `CELL_LOOKUP_POSITIVE_TTL_SECONDS` (60).
  - Misses are kept for `CELL_LOOKUP_NEGATIVE_TTL_SECONDS` (10).
  - Both caches are capped at `CELL_LOOKUP_MAX_CACHE_ENTRIES` (100000) and cleared on every snapshot.
- **If a refresh fails**, the last snapshot keeps serving, however old it is. `/readyz` fails only until the first snapshot loads. Staleness is alerted on through `cell_lookup_snapshot_age_seconds`; it is not tied to readiness, because every pod going unready together would drop all traffic.
- **Expiry** (`expires_at`, Unix seconds) is enforced at lookup, not only by DynamoDB TTL.

## Configuration

| Variable | Used by | Meaning |
|---|---|---|
| `CELL_LOOKUP_TABLE` | both | Route table name |
| `CELL_LOOKUP_CELL_INDEX` | sync | GSI on `cell` (default `by-cell`) |
| `CELL_LOOKUP_DYNAMODB_ENDPOINT` | both | Optional endpoint (DynamoDB Local); default is the regional endpoint |
| `CELL_LOOKUP_CELLS` | serve | Comma-separated cells, e.g. `cell-0,cell-1,cell-2,cell-3` |
| `CELL_LOOKUP_HASH_KEY_<CELL>` | both | Hex `api_keys_hash_key` of the cell (`cell-0` -> `CELL_LOOKUP_HASH_KEY_CELL_0`), from Vault |
| `CELL_LOOKUP_LISTEN` / `CELL_LOOKUP_ADMIN_LISTEN` | serve | `0.0.0.0:9191` (ext_authz) / `0.0.0.0:9090` (`/healthz`, `/readyz`, `/metrics`) |
| `CELL_LOOKUP_PATH_RULES` | serve | Replaces the built-in path rules (`*` one segment, `**` the rest, one `{merchant_id}`) |
| `CELL_LOOKUP_CELL` | sync | The cell being synced |
| `CELL_LOOKUP_DATABASE_URL` | sync | Postgres URL of the cell's read-only user. Without `sslmode` in the URL, TLS uses `verify-full` |
| `CELL_LOOKUP_DB_ROOT_CERT` | sync | CA bundle path, e.g. `/etc/ssl/rds/ca.pem` |
| `CELL_LOOKUP_MAX_DELETE_RATIO` / `CELL_LOOKUP_MIN_DELETES` | sync | One run may delete the larger of 20 % of the cell's items or 10 items; `--force` overrides |
| `CELL_LOOKUP_PREFLIGHT_CELL` | serve | Cell for CORS preflights; default the first of `CELL_LOOKUP_CELLS` |
| `RUST_LOG` | both | Log filter. Logs are JSON; signing and driver crates are held at `warn` |

AWS credentials and region come from the default chain: IRSA in the cluster, `AWS_REGION`.

## Sync safety

The sync touches only one cell's data:

- It writes only items whose `cell` is its own cell.
- It deletes only items it read through the `by-cell` index. Revoked and expired keys are dropped this way.

A run makes no changes and fails in these cases (`--force` overrides):

- The source returned no rows.
- The run would delete more than the limit allows.

A merchant id that another cell already holds (a move in progress) is skipped, not taken over. The count is logged as `foreign`.

`--dry-run` prints the counts only. Logs never contain keys, hashes, plaintext publishable keys or the database URL. Metric labels are fixed enums only.

## Metrics (`/metrics` on the admin port)

| Metric | Labels / meaning |
|---|---|
| `cell_lookup_lookups_total` | `result`: `found`, `unknown`, `no_route`, `unavailable`, `preflight`. `source`: `snapshot`, `fresh`, `negative`, `table`, `skipped` |
| `cell_lookup_lookup_duration_seconds` | Histogram, 25 µs to 100 ms |
| `cell_lookup_refreshes_total` | `result`: `ok`, `error` |
| `cell_lookup_snapshot_entries` | Items in the loaded snapshot |
| `cell_lookup_snapshot_age_seconds` | `-1` before the first load |

## Build and test (offline, from the shared registry cache)

```sh
cd services/cell-lookup
cargo build --offline --locked
cargo fmt --check
cargo clippy --offline --locked --all-targets -- -D warnings
cargo test --offline --locked
```

`aws-sdk-dynamodb` and `tokio-postgres` are not in the offline registry, so the crate uses replacements:

- **DynamoDB:** a small JSON-protocol client signed with `aws-sigv4` (`src/store/dynamodb.rs`).
- **Postgres:** `sqlx-postgres` with rustls.

## Run locally

```sh
# DynamoDB Local on :8000 with the table from INTEGRATION.md, any static credentials
export AWS_REGION=eu-central-1 AWS_ACCESS_KEY_ID=local AWS_SECRET_ACCESS_KEY=local
export CELL_LOOKUP_TABLE=pay-dev-euc1-cell-lookup CELL_LOOKUP_DYNAMODB_ENDPOINT=http://127.0.0.1:8000/
export CELL_LOOKUP_HASH_KEY_CELL_0=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
export CELL_LOOKUP_DATABASE_URL='postgres://db_user:db_pass@127.0.0.1:5432/hyperswitch_db?sslmode=disable'
cargo run --offline -- sync --cell cell-0
CELL_LOOKUP_CELLS=cell-0 cargo run --offline -- serve
curl -si -X POST localhost:9191/payments -H 'api-key: <a dev key>'
```
