---
name: github-issue
description: Create GitHub issues with forms, labels, severity, SLA and milestone.
---

# github-issue

- Use the issue forms (`feature`, `bug`, `task`, `security-finding`, `postmortem-action`); every field is required.
- Labels: `area/*`, `severity/critical|high|medium|low`, `pci`, `source/*`, `blocked`. SLA: critical 7 days, high 30.
- One milestone per specification; tasks.md items become issues in that milestone; PRs reference them with `Closes #N`.
