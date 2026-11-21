---
description: Decide whether the change touches the CDE and attach a PCI DSS checklist to the PR.
---

# /pci-impact

1. Match the changed files against `policy/cde-paths.yaml`.
2. If the CDE is touched, set the commit trailer `PCI-Impact: yes`, add the PCI DSS checklist to the PR description and ask pci-auditor for a conclusion; otherwise `PCI-Impact: none`.
