---
name: commit-and-pr
description: Write commits and PR descriptions following the repository conventions.
---

# commit-and-pr

- Conventional Commits in English: `type(scope): imperative summary`, at most 72 characters; types `feat fix perf refactor test docs build ci chore revert`; scopes from the allowed list.
- Trailers: `Refs: #N` always; `Spec: specs/NNN-slug#Tn` when derived from a spec; `PCI-Impact: none|yes` on CDE paths.
- One commit, one reason; each commit builds and passes tests; mechanical changes and refactoring go in separate commits before behaviour changes.
- PR description sections: Why, Changes (one entry per commit title), How verified, Risk and rollback, PCI impact, Checklist; at most 400 changed lines excluding generated files.
- No AI co-authorship marks in commits or PR text.
