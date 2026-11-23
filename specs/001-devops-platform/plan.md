# Plan: 001-devops-srs

## Components and boundaries

Nine requirement files under `docs/requirements/`, one ADR under `docs/adr/`, and edits to `docs/glossary.md` and `docs/requirements/README.md`; one owner (`docs-writer`), no code.

- Source: the architecture source split by section (memory `architecture/README.md`), dated 2026-11-20, revision 2026-11-21, SHA-256 prefix `5daa9b628fe392a3`. Agents read it by this absolute path (it is outside their worktrees); `srs.md` records the same title, date and prefix. If the checksum changes the writer stops and the human decides between an addendum and a rewrite.
- ID areas: functional `INF`, `DAT`, `SEC`, `DEL`, `OBS`, `COST`; `NFR-` only in `nfr.md` with the areas `SLO`, `CAP`, `REC`, `COST`, `COV`; the area files cite them.
- File map:
  - `nfr.md` (T2): all numeric targets (sections 1, 2, 8 thresholds, 12 limits, 13, 21.5 capacity, 25.2, 25.4, D2 to D8).
  - `infrastructure.md` (T3): sections 2 (cells, edge path, graceful shutdown, load shedding, MSK settings), 3, 4 (clusters), 17, 20.8, 21.1, 26; D6; the infrastructure part of D7 (non-compute prepared in advance, compute from Terraform at the switch, RTO budget, plan B).
  - `data-and-recovery.md` (T4): sections 5, 19, 24, 21.2, 21.3, backup tiers of 21.5; from section 2 the write path through Redis streams and drainer, PSP interaction timings, patterns, CAP/PACELC; D2 to D5 and the data part of D7; D8. It cites the infrastructure requirements of T3 and the policies of T7.
  - `security-and-access.md` (T5): sections 6 (platform controls), 16, 20.1, 20.3, 20.4, 20.12, 23 including 23.5, break-glass access from 14.
  - `delivery.md` (T6): sections 4 (delivery), 9, 14 zero manual actions, 18 infrastructure autotests, 27.5, 27.6; D1; the migration Job snapshot step of D3 (section 17), the only place that defines it.
  - `policy-and-cost.md` (T7): sections 10, 12 controls, 20 (the rest), the FinOps threshold of 21.5, 22; the policies of D2 and D3 (no stateful resource without a backup plan, no schema change without an available snapshot) and the SCP allow list of D7.
  - `observability-and-testing.md` (T8): sections 7, 8, 15, 25, 20.6 (on-call, PagerDuty escalation).
  - `traceability.md` (T9) is written last; T10 sets `status: baseline`.
  - `docs/adr/0017-recovery-region-data-replication.md` (T11): the ADR of D6 and D7.
- Section 13: one traceability row per ADR; an ADR that carries a requirement maps to its IDs, otherwise "design decision only".
- Style: one row `| ID | Requirement | Verification | Implementation | Source |`; the requirement is a "shall" sentence, the implementation names the mechanism; no introductions, no explanation of obvious steps, no restating of source text beyond what a requirement needs.
- Precedence: owner decisions, then section 1, then the rest; an unsettled contradiction is an open issue in `srs.md`.

## Changes per domain

- infra: none.
- Helm charts and environment values: none.
- crates: none.
- policy: none.
- observability: none.
- docs: the nine files under `docs/requirements/`, `docs/adr/0017-recovery-region-data-replication.md`, `docs/glossary.md` (new terms: cell, spare cell, error budget, write-behind, drain lag SLO, working region, recovery region), `docs/requirements/README.md`.

## ADRs

One new ADR (T11) records the region model of D6 and D7 and supersedes the warm standby of ADR-004 and section 3; other ADR numbers are cited as "ADR-0NN (architecture section 13)" until their files exist.

## Rollout and rollback

One pull request per task, each from its own branch from `main` and merged by a human after CI and review. The baseline commit (T9) is the last commit of its pull request and starts only after T1 to T8 and T10 are done. Rollback is reverting the merge; nothing depends on the files yet. After the baseline exists, changes go through addenda and the gate refuses direct edits.

## Test plan

- AC2, AC3 and the traceability part of AC5 run as `tools/lint/srs-lint` on every task and in the integrate phase.
- AC1, AC6, AC8, AC12 run in the integrate phase (`ls`, `/glossary-check`, the Cyrillic search, `tools/lint/spec-gate` on the baseline commit).
- AC4, the row-by-row part of AC5, AC7, AC9, AC10 and AC11 are signed off by the human reviewer of the pull request, because the review agents never see the source document.

## Alerts and dashboards

None: documentation does not run in any environment.
