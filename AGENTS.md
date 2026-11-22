# AGENTS.md

Rules shared by every agent of this repository. Agent definitions in `.claude/agents/` add only their role and owned paths.

## Context policy

```yaml
context_policy:
  load_on_demand: true
  always_read: [AGENTS.md, manifests/project.yaml]
  conditional_read:
    - manifests/environment.yaml      # sizing, capacity types, per-env differences
    - manifests/infrastructure.yaml   # module inventory, outputs, live layout
    - manifests/constraints.yaml      # hard rules, SLO and recovery numbers, owner decisions D1-D8
    - architecture/<NN>-<slug>.md     # one source section, only when a manifest is not enough
    - specs/<own spec only>/
  avoid: [rereading_all_specs, duplicating_documentation, repeating_approved_decisions, reading_the_full_architecture]
```

- Read a file only when the task needs it; read a part of a large file (`grep`, line ranges), not the whole.
- The architecture source is in Ukrainian at `~/.claude/projects/-data-vlad-portfolio-payments-platform/memory/architecture/`; open the one section the task names.
- Owner decisions in `manifests/constraints.yaml` override the architecture source; do not restate them in code comments or docs.

## Writing

- English only. Comments: one line, why not what; no docstrings or block comments (`vendor/` excluded).
- Layout: one concern per directory, at most 10 files (README excluded); a Terraform root holds only wiring and calls `modules/<concern>/`; each module has `versions.tf`, `variables.tf`, `main.tf`, `outputs.tf`, a README of at most 10 lines and `tests/`; configuration data goes under `config/`. Directory names lower-case kebab-case.
- Names `pay-<env>-<region-short>-<component>`; tags from `manifests/project.yaml`.
- Use the terms of `docs/glossary.md`.
- No card data anywhere; images by digest; no secrets in files.

## Boundaries

- Write only inside your `owns` (`.claude/orchestration.yaml`); for another domain write `specs/<spec>/handoffs/<you>-<to>.md`.
- Never run `terraform apply`, `kubectl`/`helm` mutations, mutating `aws` calls, `git push` or merges. Do not commit: the orchestrator commits.
- Work in the worktree path the task gives you; your branch is `agent/<area>-<slug>`. The orchestrator moves GitHub issues and writes `specs/<spec>/progress/` files; you do not.

## Verification (run what applies, in the directory you changed)

- Terraform: `terraform init -backend=false && terraform fmt -check && terraform validate && terraform test`, then `tflint`.
- Helm: `helm lint --strict`, `helm template ... | kubeconform -ignore-missing-schemas -summary`, `helm unittest`.
- Policies: `opa test <dir>`, `opa fmt --fail -l`, `kyverno test <dir>`. Alerts: `promtool check rules`, `promtool test rules`.
- Workflows: `actionlint`. Python: `python3 -m py_compile`, `python3 -m unittest`. Layout: `tools/lint/structure`.

## Reviewers (read-only agents)

- You see only the diff and the spec; you never review a change you wrote.
- Rate every finding low, medium or high (high blocks); give file and line, the risk and a concrete fix; return the report as your final message.

## Report (at most 300 words)

Files or directories written, the result of each check, anything skipped or assumed, placeholders to replace. No restating of the task.

## Specification tiers

| Tier | When | Needed |
|---|---|---|
| trivial | at most 3 files, one domain, no CDE path | commit with `Refs: #N` and `Spec-Exempt: trivial` |
| small | one or two domains, no CDE path | `specs/NNN-slug/spec.md` only, `tier: small`, at most 30 lines |
| full | several domains, CDE paths or architecture changes | `spec.md`, `plan.md`, `tasks.md`; reviewed by `spec-reviewer` |
