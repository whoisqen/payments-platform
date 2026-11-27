# runbook-roles

Roles of the runbook workflows in one environment account: `<prefix>-<env>-glob-runbook-diagnose` (main, `runbook-diagnose.yml`) and
`<prefix>-<env>-glob-runbook-actions` (GitHub Environment `runbook-<env>`, `runbook-actions.yml`). Each may start, follow, stop and tag
executions of `<prefix>-runbook-*` documents and pass only its own `<role>-exec` to SSM. Both exec roles read (ReadOnlyAccess);
`actions_exec_policy_arns` adds the write rights the documents' action steps need.
Test: `terraform init -backend=false && terraform test`.
