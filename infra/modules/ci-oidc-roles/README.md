# ci-oidc-roles

GitHub OIDC provider and roles `pay-<env>-glob-tf-plan` and `pay-<env>-glob-tf-apply-<component>` (section 23.3).
Trust is pinned to the repository and the ref: pull requests for plan (read-only), `main` and `release/*` (`apply_refs`) for apply roles; no other subject can assume an apply role.
Plan reads metadata, the state of its environment and writes only `.tflock` files; no secret or object reads.
An apply role gets its named actions on named resources, its own state prefix `<env>/<component>/`, a 1 hour session,
the permissions boundary, and a deny on roles created without that boundary. `*`, `iam:*` and wildcard resources are rejected.
Test: `terraform init -backend=false && terraform test`.
