# Plan: 002-repository-as-code

## Components and boundaries

- `infra/github/` (terraform-engineer): one root module, provider `integrations/github` with GitHub App authentication (`app_auth` from `GITHUB_APP_ID`, `GITHUB_APP_INSTALLATION_ID`, `GITHUB_APP_PEM_FILE`), S3 backend block with placeholder bucket, state key `github/terraform.tfstate`. No resource is applied here.
- Layout: the root holds only wiring (`main.tf`, `variables.tf`, `versions.tf`, `backend.hcl.example`); each concern is a module under `modules/` with its own `tests/` (`terraform test`, mocked provider); `config/owners.yaml` is rendered by `modules/codeowners` with `yamldecode`; the layout is enforced by `tools/lint/structure`.
- Repository files (ci-engineer): `.github/` templates and the drift workflow, `SECURITY.md`, `renovate.json5`, `.pre-commit-config.yaml`, `commitlint.config.js`. These root files are added to the `owns` of ci-engineer in `.claude/orchestration.yaml`.
- Interfaces: the ruleset names the required status checks `ci-gate` and `spec-gate`; the tag rule bypass actor is the GitHub App of the tagging workflow; `commitlint.config.js` and `spec-gate` share the type and scope lists (single source: the list in `CLAUDE.md`).

## Changes per domain

- infra: `infra/github/**` (T1 to T3).
- Helm charts and environment values: none.
- crates: none.
- policy: none.
- observability: none.
- docs: `infra/github/README.md`; CI files in `.github/` and root (T4).

## ADRs

Not needed: no architecture decision changes.

## Rollout and rollback

Pull request after review. Nothing is applied: the first `terraform plan` against the real organization is a separate human step after the owner replaces the placeholders. Rollback is reverting the merge.

## Test plan

`terraform fmt -check`, `validate`, `tflint`, `terraform test` (mocked provider), `gitleaks`, `actionlint`, `pre-commit validate-config`, `renovate-config-validator`, `commitlint --print-config`, and the parity test of AC8 run in the build phase and again in the integrate phase.

## Alerts and dashboards

The drift workflow of T4 alerts on any difference; the alert route is a variable (placeholder) until the on-call tooling exists.
