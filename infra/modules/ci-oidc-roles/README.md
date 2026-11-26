# ci-oidc-roles

GitHub OIDC provider and roles `pay-<env>-glob-tf-plan` and `pay-<env>-glob-tf-apply-<component>` (section 23.3).
Trust is pinned to the repository and the ref: `main` for plan (read-only, nightly drift), `main` and `release/*` (`apply_refs`) for apply roles; no pull request subject can assume any role, PRs run `terraform test` with mock providers.
Plan reads metadata, the state of its environment and writes only `.tflock` files; no secret or object reads.
An apply role gets its named actions on named resources, its own state prefix `<env>/<component>/`, a 1 hour session,
the permissions boundary, and a deny on roles created without that boundary. `*`, `iam:*` and wildcard resources are rejected.
`plan_refs` accepts only `refs/heads/main`; `ecr_read_repository_arns` creates `<prefix>-<env>-glob-ecr-read` (main only, read-only images). `environment` may be shared-services.
Test: `terraform init -backend=false && terraform test`.
