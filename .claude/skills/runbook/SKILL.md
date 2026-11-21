---
name: runbook
description: Write a runbook: symptom, diagnostics, actions, escalation, SSM document.
---

# runbook

- Structure: symptom, diagnostics (a script that collects metrics, events and logs into one report), actions (scripts run through GitHub Actions `workflow_dispatch` with audit), escalation, SSM document.
- Every alert links to its runbook through `runbook_url`; CI checks the file exists and has diagnostic steps.
