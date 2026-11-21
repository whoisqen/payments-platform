---
name: cde-change
description: Pre-change checklist for anything that touches the cardholder data environment.
---

# cde-change

- Segmentation: no new path from outside the CDE; egress only via Network Firewall allowlist.
- Logging: no PAN or CVV anywhere; card fields use `Secret<T>`; masking keeps the first 6 and last 4 digits.
- Keys: only the locker role may call `kms:Decrypt` on the locker key; no human role gets it.
- Approval: CODEOWNERS (two approvals on CDE paths), trailer `PCI-Impact: yes` and a `/pci-impact` conclusion; run pci-auditor.
- Never use production data in lower environments.
