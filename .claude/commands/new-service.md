---
disable-model-invocation: true
description: Scaffold a new service with alerts and a failure-mode catalog stub.
argument-hint: <name>
---

# /new-service

Argument: `$ARGUMENTS` (<name>).

1. Create the chart on `platform-common`, Dockerfile, ServiceMonitor, probes, PDB and NetworkPolicy.
2. Create the failure-mode catalog stub in `observability/coverage/catalog/` from an FMEA of the service, and baseline alerts with runbooks.
3. Add the service to the architecture model (`docs/architecture/workspace.dsl`) and the glossary if it introduces terms.
