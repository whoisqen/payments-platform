---
description: Analyse an alert read-only and draft a postmortem.
argument-hint: <alert>
---

# /incident

Argument: `$ARGUMENTS` (<alert>).

1. Open a prod access request; the session gets credentials for 1 hour only after on-call approval. Work only through the sanitizing `obs-gateway`.
2. Collect with one diagnostic script: metrics, events and logs; list recent deployments, the affected PSP or merchant and top errors.
3. Propose rollback first (Argo Rollouts abort, revert PR to the previous digest, feature flag off), then config or code fixes.
4. Draft the postmortem with the `postmortem` skill; actions become issues labelled `postmortem-action`.
