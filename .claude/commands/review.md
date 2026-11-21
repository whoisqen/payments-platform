---
description: Run parallel reviewers on the current diff and produce one consolidated report.
---

# /review

1. Select reviewers by changed paths: terraform-reviewer for `infra/**`, k8s-reviewer for `deploy/**`, migration-checker for migrations, pci-auditor when `policy/cde-paths.yaml` matches, security-auditor always, finops-analyst for `infra/**`, spec-reviewer when `specs/**` changed.
2. Reviewers get only the diff and the spec, in read-only detached worktrees.
3. Consolidate findings by severity; `high` blocks. Write the review-report marker `<!-- review-report: <sha> -->` for the current head SHA.
