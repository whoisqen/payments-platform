# tests

The platform's own tests: `smoke/`, `component/`, `integration/`, `contracts/`, `e2e/`, `load/`, `chaos/`. Upstream tests live in `vendor/hyperswitch-e2e/`.

Offline suites need only Python 3 and PyYAML; no network, AWS, card data or secrets. All of them at once: `make test-python`.

## Pipeline stages

Each stage runs only after the previous one is green; within a stage the rows run top to bottom, rows with the same step in parallel.

| Stage | Trigger and workflow | Step | Checks | Blocks |
|---|---|---|---|---|
| 1 pull request | `pull_request`, `ci.yml`, gate `ci-gate` | static | `lint-fast` (actionlint, repo lint, gitleaks), `commitlint`, `spec-gate`, `security.yml`, `lint-report` (ruff, yamllint, tflint, kube-linter) | yes; `lint-report` only with `LINT_STRICT` |
| | | unit | Rust nextest of the changed crates, Python (incl. offline `component/`, `integration/`), `helm unittest`, `terraform test`, promtool, OPA, Kyverno, node tests of `load/` | yes |
| | | component | router, drainer, scheduler and locker as binaries against Postgres and Redis (`component/run.py`), migration round trip, `helm template` + kubeconform, `terraform validate` | yes |
| 2 commit | push to `main`, jobs of `images.yml` after the build | image smoke | the built images, loaded into an ephemeral kind cluster (`scripts/kind`, `deploy/local` environment `ci`), start and answer `/health` | yes |
| | | integration | `integration/run.py` against the edge of the kind cluster (dummy connector), `contracts/`, read-only `terraform plan` of changed stacks | yes; a red run stops the dev promotion |
| 3 deploy | Argo CD sync | dev, stage | PostSync smoke (`smoke/live.py`) | yes, rollback |
| | `smoke-green-stage`, jobs of `promote.yml` | stage verify | `integration/run.py` against `STAGE_API_URL`, perf gate on the latest k6 TestRun in VictoriaMetrics | yes; the prod pull request waits for it |
| nightly | `nightly.yml` calls `ci.yml` with `full: true` | all except Rust | unit and component of every area | opens an incident issue |
| weekly | `nightly.yml` Sunday 02:00 UTC, `rust-ci` | Rust | fmt, clippy, unit and component tests of both Rust workspaces, every crate | opens an incident issue |

Stage 1 targets 10 minutes for a pull request without Rust changes; a Rust change adds the build of its workspace (debug profile, `Swatinem/rust-cache`).

## Linters in report mode

ruff (`E9`, `F`, `B`), yamllint (relaxed, no line length), tflint (recommended preset and the AWS ruleset) and kube-linter (security checks only) are configured in `tools/ci/lint/`. They report findings as warnings and annotations. One switch makes them blocking: the repository variable `LINT_STRICT=true` in CI, `make lint-report LINT_STRICT=1` locally.

## Suites

- `smoke/`: a synthetic payment (create, capture, read, refund) through a fake edge and test PSP for every cell, probe and port checks of every chart, and `live.py`, the PostSync smoke. Budget 90 seconds.
- `component/`: `run.py router drainer scheduler locker` starts each binary from `COMPONENT_<NAME>_BIN` with generated keys, waits for its health endpoints and stops it with SIGTERM; `make component`. Offline tests use `fake_service.py`.
- `integration/`: `run.py` bootstraps a merchant, API key and dummy connector through the admin API, then runs health, auth, create-get-cancel, duplicate id and unknown payment scenarios; the confirm and refund path reuses `smoke/live.py` when `INTEGRATION_PAYMENT_TOKEN` is set. Offline tests use `fake_router.py`. Local stack: `make up` (kind, see `scripts/kind/README.md`).
- `contracts/`: environment values against `deploy/charts/*/values.schema.json`, and alert `failure_mode` and `runbook_url` against `observability/coverage` and `docs/runbooks`.
- `e2e/`: promotion dev to stage by image digest through `tools/ci/images_yaml.py` and `tools/ci/digest_compare.py`.
- `chaos/` and `load/` have their own READMEs.

## What a change runs

The `changes` job reads `tools/ci/areas.yaml` and starts only the checks of the areas a pull request touches; `lint-fast`, `commitlint` and `spec-gate` always run.

| Change | Runs |
|---|---|
| `docs/`, `specs/`, `manifests/`, root Markdown | nothing beyond the always-on checks |
| `config/**` | Python (the `tools/config` tests of the generated files) |
| `Makefile`, `mise.toml`, `tools/ci/**`, `ci.yml`, `security.yml` | every area except the Rust build |
| other workflows | the workflow checks (actionlint, zizmor) |
| `vendor/hyperswitch` or `vendor/card-vault` (including `Cargo.lock`) | that workspace only, changed crates |
| `rust-toolchain`, the Rust or cargo-nextest line of `mise.toml` | both Rust workspaces, every crate |
| `infra/`, `deploy/`, `policy/`, `observability/`, `docker/`, `tests/`, `scripts/` | their own area (Terraform, Helm, policy, alerts, Docker, Python, Node, compose) |
| label `ci:full` | every area and every crate |

A guard test fails when a new top-level directory or file is not claimed by an area, a common rule or the `lint_only` list, so nothing silently skips the heavy checks. Jobs that need Docker (component tests, the migration round trip) run pull-request code on GitHub-hosted runners: a fresh VM per job with Docker and no AWS access, never the self-hosted pools.
