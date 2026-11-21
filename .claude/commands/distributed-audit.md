---
disable-model-invocation: true
description: Final audit of distributed-systems principles and microservice patterns by distributed-systems-reviewer.
---

# /distributed-audit

Run once, when most of the platform specifications are `implemented`.

1. Run `tools/lint/spec-lint`, `tools/lint/orchestration-lint --strict`, `tools/lint/srs-lint`; stop if any is red.
2. Start `distributed-systems-reviewer` with the final-audit task (principles plus microservice patterns) over the whole repository and `docs/requirements/`.
3. Turn each `high` and `medium` finding into a new specification (a finding never edits an `implemented` one) and report the table to the human.
