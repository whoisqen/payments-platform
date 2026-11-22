---
disable-model-invocation: true
description: Create a new specification specs/NNN-<title>/ (spec, plan, tasks) using glossary terms.
argument-hint: <title>
---

# /spec

Argument: `$ARGUMENTS` (<title>).

1. Choose the tier (`AGENTS.md`): trivial needs no spec; small copies `specs/_templates/spec-small.md`; full copies `spec.md` (plan and tasks come from the architect).
2. Pick the next number NNN (never reused, no gaps) and a kebab-case slug; status `draft`, `issue: none` until the human approval.
3. After approval create the milestone `NNN-<slug>` and one issue per task, fill `issue`, then start the work.
4. Run `tools/lint/spec-lint --write-index` and `/glossary-check`; for tier full only, start `spec-reviewer` when they are green (at most two fix rounds, then the human decides).
