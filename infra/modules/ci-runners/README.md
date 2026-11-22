# ci-runners

AWS side of the ARC runner pool in the CI account: build cache bucket and keys, GitHub App key secrets (names only), runner roles per scale set, the ECR push role for main and release branches, and the External Secrets role.
ci-prod may assume the plan roles and write the cache; ci-stage pulls images; ci-pr is read-only and denied roles, registry and secrets.
Values of the secrets are set by the owner, never by Terraform.
Outputs feed deploy/platform/arc (role ARNs, secret names, cache bucket).
Test: `terraform init -backend=false && terraform test`.
