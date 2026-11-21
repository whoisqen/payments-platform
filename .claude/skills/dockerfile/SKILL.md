---
name: dockerfile
description: Write a service Dockerfile: multi-stage, distroless, pinned by digest.
---

# dockerfile

- Multi-stage on cargo-chef: chef, deps, build, distroless runtime with no shell, package manager or curl.
- `FROM` pinned by digest of the manifest list; `USER 10001:10001`; `COPY --chmod=0444`, binary `0555`; exec-form `ENTRYPOINT`; no `latest`, no `ADD` from URLs; no `HEALTHCHECK` (probes are in Kubernetes).
- Reproducible build: `cargo build --locked --release`, `SOURCE_DATE_EPOCH`, `rewrite-timestamp=true`.
- Respect `docker/budgets.yaml` and the upstream build flags in `vendor/UPSTREAM.md`; validate with hadolint, Conftest, container-structure-test.
