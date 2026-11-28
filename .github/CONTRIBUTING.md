# Contributing

How a change gets from an idea to production. The rules are enforced by hooks and CI, so a change that breaks one is stopped before review.

## Setup

```sh
make bootstrap                                   # pinned tools from mise.toml and the git hooks
make lint test                                   # every static check and offline test CI runs
```

## Branches

- `main` is the only long-lived branch. Environments are directories (`deploy/envs/<env>`, `infra/live/<env>`), never branches.
- Each change gets a short-lived branch `<type>/<issue>-<slug>`, for example `fix/181-failover-topic-key`, and its own pull request to `main`. Do not collect several changes in one branch.
- A pull request merges when `ci-gate` is green and every review thread is resolved.

## Commit messages

```
type(scope): summary in lower case, at most 72 characters

Refs: #123
Spec: specs/001-devops-platform#T4
PCI-Impact: none
```

- `type`: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`.
- `scope`: one of `router drainer scheduler locker control-center infra deploy policy observability docker ci claude docs vendor specs`.
- `Spec:` names the specification task the change implements. A change that needs no specification says why with `Spec-Exempt:` (`trivial`, `owner-directed`, `bootstrap`, `upstream-import`).
- `PCI-Impact: none|yes` is required when the change touches a path listed in `policy/cde-paths.yaml`. Use `yes` when it changes how card data, its keys or its network path are handled, and fill in the PCI checklist in the pull request.

The `commit-msg` hook (`tools/lint/spec-gate`) checks these rules locally, and CI checks them again over the whole range.

## Specifications

Larger changes start as a specification in `specs/NNN-slug/` (`spec.md`, `plan.md`, `tasks.md`). Its lifecycle is `draft → approved → in-progress → implemented` (or `superseded`). Issues are created after approval, one per task. Progress lives in `specs/<spec>/progress/Tn.md`. The tiers and templates are described in [specs/README.md](../specs/README.md).

## What the pipeline checks

| Stage | Runs on | Checks |
|---|---|---|
| Pull request | every push to a pull request | lint, commit and spec gate, DevSecOps scans, unit and component tests for the changed areas only (`tools/ci/areas.yaml`) |
| Commit | merge to `main` | rootless image build, cosign signature, SBOM, integration tests on an ephemeral kind cluster, read-only `terraform plan` |
| Deploy | Argo CD sync | smoke test after each sync; stage verification before the prod pull request |

Only high and critical scanner findings block. An accepted risk is recorded with a reason and an expiry date in `policy/security/` (for example `trivyignore.yaml`), never by switching a scanner off. The full table is in [tests/README.md](../tests/README.md).

## Changing infrastructure

- Modules live in `infra/modules/<name>` with a `README.md` and `terraform test` files; run `terraform test` in the module directory.
- Live configuration lives in `infra/live/<env>/<region>[/<cell or cluster>]/<component>`; a new module also gets a row in `docs/architecture/infrastructure/base/modules.md`; values that differ per installation come from `config/platform.yaml`, sizes from `config/environments/`.
- A pull request runs a read-only plan for the changed stacks. Applies happen after merge, per environment, through GitHub Environments; prod needs approval.

## Changing applications and charts

- Charts build on the `platform-common` library chart in `deploy/charts/`. Run `make test-helm` after a change.
- Images are built once per merge and promoted by a pull request that changes `deploy/envs/<env>/images.yaml`: dev is automatic, stage and prod need approval, prod rolls out as a canary per cell.
- Database migrations follow expand and contract; `make lint-migrations` runs squawk and an up, down, up round trip.

## Documentation

A change that alters behaviour updates its documentation page in the same pull request. Start from [docs/README.md](../docs/README.md) to find the page; new terms go into [docs/glossary.md](../docs/glossary.md).

## Upstream code

`vendor/` holds upstream Hyperswitch, the card vault and their end-to-end tests. Do not edit it. A necessary patch is recorded in [vendor/UPSTREAM.md](../vendor/UPSTREAM.md) together with the reason.

## AI agents

Coding agents follow [AGENTS.md](../AGENTS.md) and the context in `manifests/`. Their changes go through the same branches, hooks and pipeline as any other change.
