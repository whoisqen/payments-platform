# Roadmap: every part of the architecture document and the specification that carries it

Source: `payments-platform-architecture.md` (27 sections). One row per section or group of subsections. A section is done only when its specification is `implemented`. Order follows the dependencies in the last column.

| Spec | Title | Architecture sections | Depends on | State |
|---|---|---|---|---|
| 001-devops-srs | SRS of the DevOps part | requirements of 1, 3-10, 12, 15-17, 19-26, 14 (zero manual actions), 18 (autotests), 27.5-27.6 | none | approved |
| 002-repository-as-code | GitHub settings, repository files, drift | 10 (Repository as code), 9 (Environments, workflow protection), 27.5 (rulesets) | none | draft, code written |
| 003-bootstrap-landing-zone | State bucket, CI roles, AFT, accounts, OUs, SCP, Identity Center | 3 (Landing Zone), 14 (bootstrap, new accounts), 23.1-23.3 | 002 | todo |
| 004-network-edge | VPCs, TGW, Network Firewall, egress EIPs, Global Accelerator, NLB, DNS and certificates | 3 (Network), 2 (edge path), 20.8, 16 (access paths) | 003 | todo |
| 005-eks-platform | EKS, Karpenter, node classes and pools, Istio, ArgoCD, add-ons, node security | 4 (clusters, GitOps), 26, 23.4 | 004 | todo |
| 006-data-stores | Aurora (cells, locker), MemoryDB, DynamoDB, MSK, ClickHouse, OpenSearch, KMS | 5, 2 (cells, write path, CAP), 21.1, 21.3, 20.1, 20.2 | 004 | todo |
| 007-backup-restore | Backup plans, vaults, restore tests, tiers, schema-change snapshot | 19, 5 (backups), 21.5 (backup tiers), SRS D2-D5 | 006 | todo |
| 008-recovery-region | Replication to us-east-1 and us-east-2, prepared network, switch runbook, plan B, tests | 3 (DR), 21.2, SRS D6-D8 | 006, 007 | todo |
| 009-helm-charts | `platform-common`, service charts, umbrella, edge and locker charts, migrations Job, chart tests | 17, 4 (deployment strategies), 20.7 | 005 | todo |
| 010-ci-cd | Pipeline, image build, signing, SBOM, promotion, hotfix, tagging workflow, Renovate | 9, 27.5-27.6, 18 (autotests), 20.5 | 002, 009 | todo |
| 011-policy-as-code | SCP, OPA, Kyverno, Config, Semgrep, tagging schema, exceptions | 10 (Policy as code), 22, 23.9, 12 (controls), 20.9 | 003 | todo |
| 012-security-access | Vault, secrets, IAM least privilege, admin interfaces, SSO, compliance as code, threat model | 6, 16, 20.3, 20.4, 20.12, 23.2-23.8 | 005, 011 | todo |
| 013-observability | Metrics, logs, traces, dashboards, alerts, SLO rules, exporters, coverage, on-call | 7, 15, 25, 20.6, 20.11 | 005 | todo |
| 014-performance-chaos | k6, capacity model, autoscaling limits, chaos experiments, smoke tests | 8 | 009, 013 | todo |
| 015-resilience-config | Timeouts, retries, circuit breakers, budgets in Istio and charts | 24, 2 (PSP interaction, patterns) | 009 | todo |
| 016-finops | Budgets, Infracost, reservations, cost reports, scheduling | 12, 20.9 | 011 | todo |
| 017-dev-environment | Developer environment as code | 20.10 | 010 | todo |
| 018-service-configuration | Cells and merchant routing, hot-merchant split, PSP timeouts, locker capacity, Hyperswitch patches in `vendor/UPSTREAM.md` | 2, 21.1, 21.5 (locker), 6 (locker) | 006, 009 | todo |
| 019-distributed-audit | Final audit by `distributed-systems-reviewer` | all | all | todo |

## Already covered by existing tooling, not by a specification

- Section 11 (Claude Code), section 14 (directory layout), section 18 (directory tree, agent models, comments, refactoring), 27.1-27.4 and 27.7-27.8 (Git rules): `CLAUDE.md`, `.claude/`, `tools/lint/`, `tools/scripts/`.

## Rules

- A specification is written from its row here; nothing outside this table is built. A new need is a new row first.
- `001-devops-srs` supplies the requirement IDs that every specification cites in its acceptance criteria.
