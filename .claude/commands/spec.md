---
disable-model-invocation: true
description: Create a new specification specs/NNN-<title>/ (spec, plan, tasks) using glossary terms.
argument-hint: <title>
---

# /spec

Argument: `$ARGUMENTS` (<title>).

1. Pick the next number NNN (never reuse a number; no gaps) and a kebab-case slug.
2. Copy `specs/_templates/spec.md` to `specs/NNN-<slug>/spec.md` with status `draft`; ask the user for the problem, goals and acceptance criteria.
3. Do not create GitHub issues yet: `issue` stays `none` in spec.md and tasks.md. After the human approval, create the milestone `NNN-<slug>` and one issue per tasks.md item, fill in `issue`, and only then start the work (the spec gate rejects a commit for a task without an issue number).
4. Regenerate the index in `specs/README.md` (number, title, status, milestone).
5. Run `tools/lint/spec-lint`, `tools/lint/spec-lint --write-index` to refresh the index, and `/glossary-check`.
6. Only when step 5 is green, start the `spec-reviewer` agent automatically, without asking, to review `spec.md`, `plan.md` and `tasks.md` (give it the lint output); a `high` finding blocks the approval gate. Fix the findings and run it again, at most two rounds; then hand the remaining findings to the human.
