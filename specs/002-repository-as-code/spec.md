---
id: 002-repository-as-code
status: draft
owner: platform
milestone: 002-repository-as-code
issue: none
pci-impact: none
adr: []
---

# 002-repository-as-code: GitHub organization and repository settings as code

## Problem

The settings that protect the repository (branch and tag rules, required reviews, CODEOWNERS, environments, Actions permissions, security scanning) exist only as prose in section 10 of the architecture document. Nothing in the repository applies, tests or watches them, so a change in the GitHub UI is invisible and the rules that the spec gate and the PCI change-control model rely on are not enforced.

## Goals and non-goals

- Goal: describe the organization and the repository settings of section 10 in Terraform under `infra/github/`, applied by the `integrations/github` provider through a GitHub App, with every environment-specific value a variable whose default is a placeholder (`CHANGEME`) so that nothing runs against a real organization yet.
- Goal: cover exactly the rows of section 10: `github_organization_settings`, `github_repository`, a ruleset for `main`, a ruleset for tags `v*`, CODEOWNERS generated from `infra/github/owners.yaml` by `github_repository_file`, `github_repository_environment` for dev, stage, prod and cde-prod, `github_actions_repository_permissions`, and the security settings (secret scanning with push protection, CodeQL, private vulnerability reporting).
- Goal: the files of the repository that section 10 lists next to those settings exist: `.github/pull_request_template.md` (CDE change checklist), `.github/copilot-instructions.md`, `SECURITY.md`, `renovate.json5`, `.pre-commit-config.yaml`, `commitlint.config.js`, and a nightly drift workflow that runs `terraform plan` on `infra/github/` and alerts on any difference.
- Goal: every rule that the repository already enforces locally is mirrored in the ruleset: Conventional Commits with the scopes of `CLAUDE.md`, lower-case summary, signed commits, linear history, merge queue, the required checks `ci-gate` and `spec-gate`, and creation of `v*` tags only by the tagging workflow with deletion denied.
- Non-goal: applying anything, creating the GitHub App, the organization or the repository, secrets, and real team, member or reviewer names; the owner supplies them later.
- Non-goal: CI workflows other than the drift workflow, and the policy-as-code of AWS (`policy/`).
- Non-goal: GitHub Copilot code review settings beyond the instructions file (section 27.7).

## Acceptance criteria

- [ ] AC1: `infra/github/` holds only `main.tf`, `variables.tf`, `versions.tf`, `backend.hcl.example`, `config/owners.yaml`, `README.md` and `modules/{organization,repository,rulesets,environments,codeowners}/`, each module with `main.tf`, `variables.tf`, `versions.tf` and `tests/`; verified by `ls` and by `tools/lint/structure`.
- [ ] AC2: every variable that names a real object (organization, repository, teams, reviewers, GitHub App id and installation id, required check names) has a `CHANGEME` default and no value is hard-coded elsewhere; verified by `grep` for a second occurrence and by `terraform validate`.
- [ ] AC3: no secret appears in the repository; the GitHub App private key is read from the environment variable `GITHUB_APP_PEM_FILE`; verified by `gitleaks` and by `terraform validate`.
- [ ] AC4: `terraform fmt -check`, `terraform validate` and `tflint` pass on `infra/github/`; verified by running them.
- [ ] AC5: `terraform test` in every module with a mocked provider asserts each row of section 10 (private or public from the variable `visibility`, squash-merge only, auto-delete of branches, vulnerability alerts, 2 approvals of which 1 from CODEOWNERS, dismiss stale reviews, last-push approval, required checks, linear history, signed commits, merge queue, no force push, tag rule for `v*`, environment reviewers for prod and cde-prod, read-only `GITHUB_TOKEN`, allowlisted and SHA-pinned actions); verified by running `terraform test` in each module.
- [ ] AC6: `infra/github/owners.yaml` maps `vendor/hyperswitch/crates/router/**`, the locker code and `infra/live/cde-*` to the teams of section 10 and the generated CODEOWNERS contains one line per mapping; verified by a `terraform test` assertion.
- [ ] AC7: the drift workflow, `renovate.json5`, `.pre-commit-config.yaml` and `commitlint.config.js` exist and are valid for their tools, and the pre-commit configuration runs `spec-gate` at the `commit-msg` stage; verified by `actionlint`, `pre-commit validate-config`, `renovate-config-validator` and `commitlint --print-config`.
- [ ] AC8: the commit rules of `commitlint.config.js` accept every subject that `tools/lint/spec-gate` accepts and reject the same subjects; verified by a test that feeds the cases of `tools/lint/tests/test_gate.py` to both.
- [ ] AC9: no filler: every variable, rule and file carries only what an engineer cannot guess; verified by the human reviewer.

## Impact on SLO, PCI and cost

- SLO: none, no workload is touched.
- PCI: none for this change, no CDE path is edited; the CODEOWNERS and ruleset it defines are the change-control evidence for the CDE paths (two approvals), so the implementing change must not weaken them.
- Cost: none now; GitHub Advanced Security features (CodeQL, secret scanning) on a private repository are licensed per committer, to be estimated when the organization is created.

## Risks

- The repository is open source (Apache-2.0) while section 10 says private. Mitigation: `visibility` is a variable, `private` is the default of the source, and the owner decides before the first apply (open issue).
- Terraform cannot be applied or planned without credentials, so only mocked tests prove the code. Mitigation: AC5 asserts every setting, and the first real plan is a separate step by a human.
- The required check names (`ci-gate`, `spec-gate`) do not exist as workflows yet. Mitigation: they are variables with placeholders and the CI specification must create them with the same names.
- Local hooks and the ruleset can diverge. Mitigation: AC8 compares them.
- GitHub issues do not exist yet: `issue: none` until the approval.
