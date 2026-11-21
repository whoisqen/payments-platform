---
description: Run terragrunt plan for an environment with Infracost and a blast-radius summary.
argument-hint: <env>
---

# /plan-infra

Argument: `$ARGUMENTS` (<env>).

1. Run `terragrunt run-all plan` for `infra/live/<env>/`; never `apply`.
2. Run Infracost and report the monthly cost delta (above $1,000 needs FinOps approval).
3. Summarize blast radius: resources created, changed, destroyed, and which cells, accounts and regions are touched.
