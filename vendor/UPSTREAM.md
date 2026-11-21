# Upstream code

The directories `vendor/hyperswitch/`, `vendor/card-vault/` and `vendor/hyperswitch-e2e/` contain third-party code without changes. They are only refreshed from upstream and never edited by hand.

| Directory | Repository | Tag | Commit | Commit date |
|---|---|---|---|---|
| `vendor/hyperswitch/` | https://github.com/juspay/hyperswitch | none (HEAD `main`) | `b748596a95b8af82c1c550ee30876e4c08d3cffc` | 2026-11-21 (copy date) |
| `vendor/hyperswitch-e2e/` | https://github.com/juspay/hyperswitch, directory `cypress-tests/` | none (HEAD `main`) | `b748596a95b8af82c1c550ee30876e4c08d3cffc` | 2026-11-21 (copy date) |
| `vendor/card-vault/` | https://github.com/juspay/hyperswitch-card-vault | none (HEAD `main`) | `c1735e19ae6837980a8900ba33fa0770d78f5101` | 2026-11-20 |

Licenses: see `vendor/README.md`.

## What was taken

`vendor/hyperswitch/` (hyperswitch): `crates/`, `migrations/`, `config/`, `proto/` (compiled in `crates/external_services/build.rs`), `Cargo.toml`, `Cargo.lock`, `.cargo/`, `diesel.toml`, `.clippy.toml`, `.rustfmt.toml`, `LICENSE`, `NOTICE`.

`vendor/card-vault/` (card vault): `src/`, `benches/` (declared in `Cargo.toml`; the manifest does not load without them), `migrations/`, `config/`, `Cargo.toml`, `Cargo.lock`, `build.rs`, `diesel.toml`, `.config/nextest.toml`, `.rustfmt.toml`, `LICENSE`.

Not taken: `v2_migrations/`, `v2_compatible_migrations/`, `cypress-tests-v2/` (the platform runs API v1), `loadtest/` (load tests are our own k6), upstream Dockerfile and docker-compose, docs, CHANGELOG. Upstream has no `rust-toolchain.toml` or `deny.toml`; the Rust version comes from `rust-version` in `Cargo.toml` (hyperswitch 1.94.1, card vault 1.92.0).

## Upstream build flags

Our own Dockerfiles must repeat these flags.

- hyperswitch: `cargo build --profile release --features release --features v1`. `--bin` is not set, so all binaries are built; the image selects `BINARY=router | scheduler | drainer`, and for scheduler also `SCHEDULER_FLOW=consumer | producer`.
- card vault: `cargo build --release --features release`, binary `locker`.

## control-center

The code is not copied; the prebuilt upstream image is used, pinned by digest:

`docker.juspay.io/juspaydotin/hyperswitch-control-center:v1.39.0@sha256:19a4c9c15b89865798b9730445cd5a1e84820896d6383c3eed97ad6e61ce18b0`

This is a multi-arch index (linux/amd64 and linux/arm64).
