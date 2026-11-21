---
name: kyverno-policy
description: Write a Kyverno policy with tests and the audit-to-enforce lifecycle.
---

# kyverno-policy

- Policy file plus `kyverno-test.yaml` and sample `resources/` with one passing and one failing resource.
- Lifecycle: tests, 7 days in Audit, then Enforce. Exceptions use `PolicyException` with owner, reason and expiry.
- Existing rules to extend rather than duplicate: `cde-no-exec`, `require-signed-images`, `restrict-registries`, `require-pdb`, `require-probes`, `disallow-latest-tag`, `require-image-digest`.
