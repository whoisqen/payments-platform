# Addenda

A baseline requirements file (`status: baseline` in its front matter) is never edited. A change to the SRS is an addendum here, in `NNN-<slug>.md`, numbered without gaps like specifications.

- Front matter: `id` (the file name without `.md`), `status` (`draft`, `approved` or `applied`) and `spec` (the `specs/NNN-slug` that drives the change).
- Sections, each with a table, only the ones that apply:
  - `## Added`: `| ID | Requirement | Verification | Implementation | Source |` for new requirements; the ID is new and never reused.
  - `## Changed`: the same columns with the new text of an existing ID and the reason in `Source`.
  - `## Withdrawn`: `| ID | Reason |`; a withdrawn ID stays in the baseline and is never reused.
- An addendum goes in only through the spec gate: the commit that adds or changes it carries `Spec: <its own spec>#Tn` (never `Spec: none`) and the spec is `approved` or `in-progress`; `srs-lint` rejects an `approved` or `applied` addendum whose specification is not.
- Re-validation: when an addendum changes or withdraws a requirement ID that another specification cites, that specification is re-validated before the addendum can go in. An `approved` or `in-progress` specification is re-reviewed by `spec-reviewer` against the addendum and lists the addendum in its `revalidated: [NNN-slug]` front matter. An `implemented` specification is not edited; the addendum names a new specification in `follow-up: specs/NNN-slug`. `srs-lint` and the `commit-msg` gate both enforce this.
- The effective requirements are the baseline plus every `approved` or `applied` addendum in number order; `tools/lint/srs-lint --effective` prints them.
- A new baseline (a consolidated edition) is a specification of its own.
