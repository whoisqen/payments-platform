# jit-revocation-schedule

EventBridge schedule (default every 15 minutes) in the management account that starts the GitHub workflow `cde-jit-revocation.yml` on `main`
through an API destination; that workflow applies `identity-center` with `CDE_JIT_REVOCATION_RUN=true`, which destroys expired SRE-CDE grants.
The connection starts with a placeholder key: set `Authorization: Bearer <fine-grained token, Actions write on this repository>` in the console; Terraform ignores it later.
Failed dispatches (three retries) land in the dead-letter queue `<prefix>-management-euc1-cde-jit-revocation-dlq`.
Test: `terraform init -backend=false && terraform test`.
