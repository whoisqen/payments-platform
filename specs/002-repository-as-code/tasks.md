# Tasks: 002-repository-as-code

Every item is one unit of work for one agent. The `id` becomes the commit trailer `Spec: specs/002-repository-as-code#Tn`; `issue` is a GitHub issue in the specification's milestone, created after the approval (`none` until then). T1 first; T2 and T3 in parallel; T4 after T2.

```yaml
- id: T1
  title: Write the organization, repository, security and Actions settings
  agent: terraform-engineer
  paths: ["infra/github/versions.tf", "infra/github/variables.tf", "infra/github/main.tf", "infra/github/backend.hcl.example", "infra/github/README.md", "infra/github/modules/organization/**", "infra/github/modules/repository/**"]
  depends_on: []
  provides: repository settings
  requires: []
  acceptance: AC1, AC2, AC3, AC4 and AC9 hold for these files; `github_organization_settings`, `github_repository` (visibility variable, squash-merge, auto-delete, vulnerability alerts, secret scanning with push protection, CodeQL, private vulnerability reporting) and `github_actions_repository_permissions` (allowlist, SHA pinning, read-only `GITHUB_TOKEN`) are present; every real name is a `CHANGEME` variable
  issue: none

- id: T2
  title: Write the rulesets and environments
  agent: terraform-engineer
  paths: ["infra/github/modules/rulesets/**", "infra/github/modules/environments/**"]
  depends_on: [T1]
  provides: rulesets and environments
  requires: ["repository settings"]
  acceptance: AC4 and AC5 hold; the ruleset of `main` has PR only, 2 approvals with 1 from CODEOWNERS, dismiss stale, last-push approval, required checks, linear history, signed commits, merge queue, no force push; the ruleset of `v*` allows creation only to the tagging-workflow actor and denies deletion; environments dev and stage, prod with SRE reviewers and cde-prod with SRE and security, main only
  issue: none

- id: T3
  title: Write owners.yaml and the generated CODEOWNERS
  agent: terraform-engineer
  paths: ["infra/github/config/**", "infra/github/modules/codeowners/**"]
  depends_on: [T1]
  provides: codeowners
  requires: ["repository settings"]
  acceptance: AC4 and AC6 hold; the generated file has one line per mapping and the CDE paths need two approvals from the owning teams
  issue: none

- id: T4
  title: Write the repository files and the drift workflow
  agent: ci-engineer
  paths: [".github/pull_request_template.md", ".github/copilot-instructions.md", ".github/workflows/github-drift.yml", "SECURITY.md", "renovate.json5", ".pre-commit-config.yaml", "commitlint.config.js", "tools/ci/tests/commitlint-parity/**"]
  depends_on: [T2]
  provides: repository files
  requires: ["rulesets and environments"]
  acceptance: AC7, AC8 and AC9 hold; the drift workflow runs `terraform plan` on `infra/github/` nightly with OIDC-free GitHub App auth from secrets named in variables and alerts on any diff; the pre-commit file runs `spec-gate` at the `commit-msg` stage; the required check names equal those of T2
  issue: none
```
