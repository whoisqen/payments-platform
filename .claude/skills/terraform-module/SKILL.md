---
name: terraform-module
description: Create or change a Terraform module in infra/modules with tests, tags and docs.
---

# terraform-module

- Layout: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`, `tests/*.tftest.hcl`, `examples/basic/`; the module version is a git tag `<module>/vX.Y.Z`.
- Mandatory variables without defaults: `team`, `owner`, `pci-scope`, `data-class`, `backup-tier`; remaining tags come from Terragrunt `default_tags` (`environment`, `cell`, `component`, `managed-by`, `repo`).
- Write `terraform test` (mock providers) for every module; run `terraform-docs`.
- Encryption with customer managed KMS keys; no public subnets or IGW in CDE accounts; no `Action: "*"` or `Resource: "*"`.
- Renames use `moved` blocks. CI needs a `tests/` directory and `examples/` or the structure lint fails.
