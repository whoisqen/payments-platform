---
disable-model-invocation: true
description: Ask refactor-advisor for refactoring proposals on a path and drive an approved one.
argument-hint: <path>
---

# /refactor

Argument: `$ARGUMENTS` (<path>).

1. Run refactor-advisor on the path; it reports proposals as a separate item.
2. Accept a proposal only if the touched code is covered by tests; otherwise create a test-engineer task first.
3. Then run refactor-implementer; prove unchanged behaviour (tests green, `terraform plan` shows no changes, Helm render has an empty diff).
4. Keep refactoring and functional changes in separate PRs.
