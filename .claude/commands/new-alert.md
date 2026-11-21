---
disable-model-invocation: true
description: Create burn-rate rules and a runbook for an SLO.
argument-hint: <slo>
---

# /new-alert

Argument: `$ARGUMENTS` (<slo>).

1. Write or extend the Sloth file under `observability/slo/`; generate the burn-rate rules (never hand-write them).
2. Add labels `severity`, `team`, `service` and annotations `summary`, `runbook_url`, `dashboard_url`, a promtool unit test, and a runbook in `docs/runbooks/`.
3. Register the failure mode in the coverage catalog.
