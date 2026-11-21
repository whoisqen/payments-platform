---
disable-model-invocation: true
description: Check release readiness and describe how a release is identified.
---

# /release

1. A release is identified by the image digest; after a successful prod rollout in all regions the tagging workflow (the only creator of `v*` tags; creation allowed, deletion denied by the ruleset) tags the commit `vX.Y.Z` (owner's decision; replaces `rel-<YYYY.MM.DD>.<N>` of the architecture document). A `v*` tag builds nothing: it attaches release notes, SBOM and provenance.
2. Verify: green nightly load test not older than 24 hours, approvals (SRE; security for router and locker), no active change freeze (`policy/freeze.yaml`), one PR per `v*` tag with the full digest set matching the release manifest.
3. Release notes come from commit types (git-cliff). This command only checks and reports; it never merges or tags.
