# Roadmap: the single specification and what is not yet in it

Source: the architecture source (memory `architecture/README.md`, 27 sections). The platform is one specification, `001-devops-platform`, with seven milestones; every ticket is one task of its `tasks.md`.

| Milestone | Architecture sections | Tasks |
|---|---|---|
| M1 Requirements baseline | requirements of 1, 3-10, 12, 14-26, 27.5-27.6 | T1-T10 |
| M2 Repository as code | 10 (Repository as code), 9, 27.5 | T11-T16 |
| M3 Cloud foundation | 3 (Landing Zone, network), 14 (bootstrap), 2 (edge path), 20.8, 23.1-23.3 | T17-T19 |
| M4 Data stores and recovery | 5, 19, 21.1-21.3, 21.5, 2 (cells, write path) | T20-T23 |
| M5 Kubernetes platform and delivery | 4, 9, 17, 18, 26, 20.5, 20.7 | T24-T30 |
| M6 Security, policy and observability | 6, 7, 10 (policy as code), 15, 16, 20.3, 20.4, 22, 23, 25 | T31-T35 |
| M7 Verification and release readiness | 8, 18 (autotests), 25.4 | T36-T40 |

## Not yet in the specification

Each becomes a task of this specification (or a new row here first) when work on it starts: resilience configuration in Istio and charts (24), FinOps budgets, Infracost and reports (12, 20.9), developer environment as code (20.10), service configuration of cells and merchant routing (2, 21.1), the `prod` and `cde-prod` live stacks and values (human-only), the final audit by `distributed-systems-reviewer`.

## Already covered by existing tooling, not by a task

- Section 11 (Claude Code), section 14 (directory layout), section 18 (directory tree, agent models, comments, refactoring), 27.1-27.4 and 27.7-27.8 (Git rules): `CLAUDE.md`, `.claude/`, `tools/lint/`, `tools/scripts/`.

## Rules

- A task is added to `tasks.md` before its work starts; nothing outside the specification is built. Done tasks were implemented before the specification (owner-directed) and are marked in `progress/`.
- `docs/requirements` supplies the requirement IDs that acceptance criteria cite.
