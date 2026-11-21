# Requirements

Long-lived software requirements specification (SRS) of the payments platform.

- `srs.md`: scope, actors, glossary references, and the numbered requirements.
- Every requirement has a stable ID (`FR-<area>-<n>` functional, `NFR-<area>-<n>` non-functional) that is never reused.
- Change specifications in `specs/` cite these IDs in their acceptance criteria; an ADR in `docs/adr/` explains why a requirement is met the way it is.
- This directory is not frozen like an `implemented` specification: it is edited as the platform evolves, and each edit is a normal change with its own specification.

## Format

Every requirement is one table row `| ID | Requirement | Verification | Implementation | Source |`: a single "shall" statement (at most 400 characters), the verification method (test, metric, inspection, analysis or demonstration), the technical mechanism that meets it (tool, resource, setting or number; at most 300 characters), and the architecture section. No introductions and no explanation of trivial steps; detail beyond the limits goes to an ADR.
