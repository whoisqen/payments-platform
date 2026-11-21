---
disable-model-invocation: true
description: Prepare a PR for the fast hotfix pipeline. A human merges.
argument-hint: <PR>
---

# /hotfix

Argument: `$ARGUMENTS` (<PR>).

1. Prefer rollback or a flag/config change over a code hotfix.
2. Hotfix PR: label `hotfix`, no migrations (`vendor/hyperswitch/migrations/` is rejected), two approvals (SRE lead and on-call; plus security in the CDE).
3. Never merge; open an `incident` issue with the change record for PCI DSS 6.5.
