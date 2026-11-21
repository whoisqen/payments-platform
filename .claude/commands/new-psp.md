---
disable-model-invocation: true
description: Scaffold a new PSP connector.
argument-hint: <name>
---

# /new-psp

Argument: `$ARGUMENTS` (<name>).

1. Add the connector domains to the egress allowlist (`infra/network/psp-allowlist.yaml`), a secret in Secrets Manager, a circuit breaker, alerts and a feature flag (off by default).
2. Apply the `psp-connector-ops` skill: timeouts, idempotency and reconciliation. The result is one PR.
