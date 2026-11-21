# Requirements

Long-lived software requirements specification (SRS) of the DevOps part of the payments platform.

- `srs.md`: scope, actors and assumptions, ID scheme, pinned source, owner decisions with the source passages they override, withdrawn passages, terms used in another sense, open issues.
- `nfr.md`: numeric targets (load, SLOs, RTO and RPO, capacity, cost limits, coverage); the only file that defines `NFR-` IDs.
- `infrastructure.md`: AWS accounts and network, cells, Kubernetes, Helm and `deploy/` layout, recovery region on demand, node security.
- `data-and-recovery.md`: data stores, write path, backups, restore, resilience, cache warm-up.
- `security-and-access.md`: platform security controls, access, zero trust, break-glass.
- `delivery.md`: CI/CD, environments, promotion, hotfix pipeline, `v*` tags, zero manual actions, infrastructure tests.
- `policy-and-cost.md`: repository and policy as code, other as-code layers, tagging, FinOps.
- `observability-and-testing.md`: alerts, monitoring as code, load and chaos tests, incident analysis.
- `traceability.md`: source section to requirement IDs and back, one row per ADR.
- `addenda/`: changes after the baseline (`addenda/README.md`).
- Every requirement has a stable ID (`FR-<area>-<n>` functional, `NFR-<area>-<n>` non-functional) that is never reused.
- Change specifications in `specs/` cite these IDs in their acceptance criteria; an ADR in `docs/adr/` explains why a requirement is met the way it is.
- This directory is not frozen like an `implemented` specification: it is edited as the platform evolves, and each edit is a normal change with its own specification.

## Format

Every requirement is one table row `| ID | Requirement | Verification | Implementation | Source |`: a single "shall" statement (at most 400 characters), the verification method (test, metric, inspection, analysis or demonstration), the technical mechanism that meets it (tool, resource, setting or number; at most 300 characters), and the architecture section. No introductions and no explanation of trivial steps; detail beyond the limits goes to an ADR.
