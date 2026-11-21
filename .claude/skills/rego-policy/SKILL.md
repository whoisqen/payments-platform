---
name: rego-policy
description: Write an OPA/Rego policy with tests for Terraform plans, manifests or Dockerfiles.
---

# rego-policy

- Put rules in `policy/opa/<domain>/` with a `*_test.rego` next to them; cover a positive and a negative case; run `opa test`.
- Terraform rules read the plan JSON; examples: `cde_no_public`, `kms_cmk_required`, `required_tags`, `iam_no_wildcard`.
- Exceptions go in `policy/exceptions.yaml` with owner, reason and expiry; an expired exception fails CI.
