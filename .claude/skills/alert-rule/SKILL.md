---
name: alert-rule
description: Write an alert rule with labels, runbook, unit test and failure-mode catalog entry.
---

# alert-rule

- Required labels: `severity`, `team`, `service`; required annotations: `summary`, `runbook_url`, `dashboard_url`.
- SLO alerts are generated from Sloth files as multi-window burn rates (14.4 over 1 h/5 min, 6 over 6 h/30 min, 1 over 3 d/6 h); the 99.99% authorization SLO adds a 5 min/1 min window at burn rate 50.
- Every alert has a promtool unit test (fires on the problem series, silent on a short spike) and a runbook with diagnostic steps.
- Add the failure mode to `observability/coverage/catalog/` with `detect_within`; alerts on non-existent metrics do not count.
