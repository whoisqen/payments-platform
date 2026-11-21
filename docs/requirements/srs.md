---
status: draft
---

# Software requirements specification: DevOps part

## 1. Scope

The SRS covers the DevOps part of the platform: AWS accounts and network, Kubernetes and delivery, data protection and recovery, security controls, observability, CI/CD and everything managed as code. The requirement files are `nfr.md`, `infrastructure.md`, `data-and-recovery.md`, `security-and-access.md`, `delivery.md`, `policy-and-cost.md`, `observability-and-testing.md`; `traceability.md` maps source sections to IDs.

Out of scope:

- Business behavior of the payment services: PSP routing, merchant API authentication, webhook signing, routing of payments between cells by hash, card tokenization logic. Sections 2 and 6 of the source are in scope only for their platform controls.
- The repository process: section 11; in section 14 the directory tree, directory naming and the glossary extract; in section 18 the directory tree (including the layout of `infra/` and `policy/`), agent models, code comments and refactoring; sections 21.4 and 27.1 to 27.4, 27.7, 27.8; the Claude Code bullet of 21.5. `CLAUDE.md` governs them.
- Design rationale and operating procedures (ADRs, runbooks); the SRS links to them as "ADR-0NN (architecture section 13)".
- Changing code, infrastructure or policy, and translating the source.

## 2. Actors and assumptions

- Actors: `merchant` (the API consumer, never a platform operator), SRE on-call, platform engineer, security engineer (PCI), FinOps owner, auditor, CI and automation roles (Atlantis, ArgoCD, GitHub Actions), Claude Code agents with read-only access to observability.
- The platform is a payment orchestrator over Hyperswitch; the components are router, locker, drainer, scheduler, control-center and analytics.
- Frankfurt (eu-central-1) is the working region; us-east-1 and us-east-2 are recovery regions (D6, D7).
- Four working cells and one spare cell; locker and its Aurora are shared by all cells.
- A PSP timeout puts a payment in the `unknown state`; `sync` resolves it; a charge is never retried automatically.
- Migrations are expand-contract only; `down.sql` is never applied in prod.
- Environments: ephemeral (`pr-N`), dev, stage, prod; the CDE is separated into its own AWS accounts.
- Card data (PAN, CVV) never appears in logs, traces, metric labels or fixtures.
- Requirements describe what the DevOps part provides; the mechanism sits in the implementation column, rationale in ADRs.

## 3. ID scheme

- Functional: `FR-<area>-<n>` with areas `INF`, `DAT`, `SEC`, `DEL`, `OBS`, `COST`.
- Non-functional: `NFR-<area>-<n>` defined only in `nfr.md` with areas `SLO`, `CAP`, `REC`, `COST`, `COV`; the other files cite them.
- An ID is never reused or renumbered; a withdrawn requirement keeps its ID.
- Row format: `| ID | Requirement | Verification | Implementation | Source |`.
- Requirement: one "shall" statement, at most 400 characters. Implementation: tool, resource, setting or number, at most 300 characters. Source: architecture section or owner decision.
- Verification: exactly one of `test`, `metric`, `inspection`, `analysis`, `demonstration`.
- Precedence on a conflict: owner decisions D1 to D8, then section 1 of the source, then the other sections. A contradiction that none of them settles is an open issue (section 8), never a requirement.
- After the baseline is confirmed, a change is an addendum (`docs/requirements/addenda/README.md`).

## 4. Source

- Title: "Payments Platform: architecture and operations" (Ukrainian original, kept in the Claude project memory as `payments-platform-architecture.md`).
- Date: 2026-11-20; revision: 2026-11-21.
- SHA-256 prefix: `5daa9b628fe392a3`.
- A changed checksum stops the writers; the human decides between an addendum and a rewrite.

## 5. Decisions of the owner

Each decision is followed by the source passage it overrides.

- D1: version tags `v*` (SemVer `vX.Y.Z`: breaking change major, `feat` minor, `fix` patch), created only by the tagging workflow after a successful prod rollout in all cells; creation allowed and deletion denied by the ruleset; a tag builds nothing and attaches changelog, SBOM and provenance; the version identifier stays the image digest.
  - Overrides: `rel-<YYYY.MM.DD>.<N>` tags set by `promote` (section 9 pipeline and 27.5) and the `rel-*` row of the 27.6 table.
- D2: for Aurora PostgreSQL (every cell and locker) and DynamoDB (merchant-to-cell map): base backup plus point-in-time recovery to any second in the retention; data loss on restore at most 5 minutes; automatic daily restore verification; alert when the latest restorable time lags more than 5 minutes for 10 minutes; policy denies a stateful resource without a backup plan, the section 19 exception list being the only way around.
  - Overrides: section 5 backup tiers (gold row) and section 19 rows for Aurora and DynamoDB (snapshot every 6 h, 5 min PITR RPO) and the weekly restore verification.
- D3: MemoryDB, ClickHouse and Velero are backed up hourly with retention 35 days, replicated across AZs; MemoryDB payment data is duplicated in Aurora within the drain lag SLO; MemoryDB has no point-in-time recovery and is rebuilt from Aurora; before every migration or schema change (Aurora, DynamoDB, ClickHouse, OpenSearch) the migration Job takes an on-demand snapshot labelled with the change, starts the change only when it is `available`, and the snapshot is kept 35 days.
  - Overrides: section 19 rows MemoryDB (6 h, 7 days), ClickHouse (hourly increment, 30 days), Velero and EKS state (daily, 14 days), and the section 5 and 19 frequencies; section 17 has no snapshot step before a migration.
- D4: restore of an application database in Frankfurt after a logical error at most 30 minutes into prepared capacity; `backup_restore_duration_seconds` per store with an alert at 80% of the target and a size trend; hot storage for recent copies; zstd for self-managed backups, compressed before encryption, parallel streams; VPC endpoints for S3; restore role, KMS access and quotas prepared; restore is code with only the two-person PR approval manual; independent databases in parallel; `pg_prewarm` before traffic.
  - Overrides: section 19 restore verification, the `RestoreTooSlow` condition ("above target", no number) and the quarterly full restore; section 1 RTO column for application databases.
- D5: object-based backups (ClickHouse, Vault, OpenSearch, Velero, exports) move to a colder tier at 7 days and a still colder one at 14 days by Terraform lifecycle rules; the monthly 7-year archive goes to the coldest tier; restore targets apply to the hot tier and colder tiers state their own restore time; native tiers stay for Aurora, DynamoDB and managed snapshots; AWS minimum days are checked at implementation.
  - Overrides: section 19 flat retention columns for the S3-based stores and section 5 backup tiers (no tiering).
- D6: Frankfurt is the only writing region, with three AZs for high availability; us-east-1 is the recovery region that receives data and backups but runs no instance or cluster, all compute is Terraform and Terragrunt created at the switch; no active-active, no standby cluster; semi-automatic switch (ADR-015) with automatic detection and fencing and one on-call confirmation; us-east-2 is the second recovery region for when compute cannot be created in us-east-1.
  - Overrides: section 1 (two regions, eu-west-1 reserve), section 3 "DR between regions" (warm standby) and the VPC table, ADR-004, section 4 clusters per region, section 5 Multi-Region and Global Database to eu-west-1.
- D7: Aurora Global Database headless secondaries in us-east-1 and us-east-2 with lag alert at 5 s and RPO budget 10 s, managed RPO (`rds.global_db_rpo`) off; DynamoDB Global Tables (MREC) replicas in both, written only from Frankfurt; MemoryDB not replicated across regions, hourly snapshots copied and rebuilt from Aurora at the switch; MSK not replicated, rebuilt from the S3 archive; S3 with Replication Time Control (15 min) and Object Lock to both; ECR replication to both; non-compute resources prepared in both regions; switch tools replicated or created inside the RTO budget; RTO 60 min (plan B 75 min), RPO per store as in `nfr.md`; plan B in us-east-2 after 10 minutes without capacity, promotion in one region under a lock; recovery VPC CIDRs 10.102.0.0/16 (us-east-1) and 10.103.0.0/16 (us-east-2); accepted risk: a repeated request after the switch with the same idempotency key can create a second charge if the key was in MemoryDB and not yet in Aurora (at most the drain lag, p99 5 s); it is found by the 5-minute PSP reconciliation with the reference id and refunded, and the write-behind rule stays.
  - Overrides: section 1 RTO/RPO table (region loss rows 1 s and 5 min, locker row, Kubernetes state row) and the paragraph below it; section 3 DR steps 3 and 4 (RTO derivation) and the SCP region list; section 5 Global Database and MemoryDB Multi-Region; section 19 rows for MSK, S3, Terraform state and Velero; ADR-003, ADR-007, ADR-013.
- D8: after a node replacement, AZ loss or recovery a cell takes traffic when at least 75% of the priority hot keys (merchant configuration, routing, limits) are in MemoryDB (`cache_warm_ratio`); the readiness probe waits at most 5 minutes, then the cell takes traffic and a non-paging alert fires.
  - Overrides: nothing; an owner addition that the source does not contain.

## 6. Withdrawn source passages

None of these is carried into a requirement.

- MemoryDB Multi-Region (sections 3, 5).
- Velero backup copy to eu-west-1 (section 4, Velero paragraph).
- S3 and Terraform state copies to eu-west-1 (sections 9 and 19).
- The cde-prod eu-west-1 VPC (section 3 VPC table).
- Clusters in each region (sections 4 and 12).
- The eu-west-1 endpoint group of Global Accelerator (ADR-007).
- The 5-minute PSP reconciliation after failover (sections 1 and 3); the window now follows D7.
- The S3 audit copy target in eu-west-1 (sections 3 and 19); the audit copy goes to us-east-1 and us-east-2.
- eu-west-1 in the SCP region allow list (section 3).
- MirrorMaker 2 (section 19).
- The quarterly full restore of a cell in the DR region (section 19).
- The 5-minute RTO derivation (section 3) and the pilot-light rationale (ADR-004).
- The locker row RPO 0 and RTO 5 min (section 1).
- The replicas "in the reserve region" of ADR-003 and ADR-013.

## 7. Terms used in another sense

`docs/glossary.md` forbids these words for the business concept; the DevOps text uses them in the sense below.

| Word | Sense used | Applies to |
|---|---|---|
| `deploy` | The `deploy/` directory and Kubernetes manifests, never promotion | Helm charts, `deploy/envs`, `deploy/platform` |
| `release` | The version tag `v*` with its GitHub release object, the `release/*` hotfix branch, the ECR release repository | D1, delivery, hotfix pipeline |
| `retry` | Transport retries of idempotent calls (Istio `VirtualService` retries, client backoff, scheduler retries of outbound webhooks); never a retry of a charge or a `sync` | Resilience, section 24 |
| `gateway` | Istio ingress gateway, Transit Gateway, NAT Gateway; never a PSP | Edge path, network |
| `transaction` | A database or MemoryDB transaction (transaction log) | Data stores |
| `user` | A person with an account in an admin tool (IAM Identity Center, Grafana, ArgoCD), never a `customer` | Access, admin interfaces |
| `client` | Software client (Kafka, Vault, TLS client certificate), never a `merchant` | Security, data |
| `order` | Sequence (ordered instance class list, rollout order), never a purchase | Plan B, upgrades |
| `failed`, `pending` | Status of a job, pod or backup (`FAILED`, `Pending`), never the state of a payment | Backups, Kubernetes |
| `replication lag` | Lag of Aurora Global Database or S3 replication between regions; the lag of the Redis stream is the `drain lag` | D7 |

## 8. Open issues

Source passages that still name eu-west-1 or a second active region, are not on the withdrawn list and need an owner decision before the writers use them:

- Section 12 cost rows: MemoryDB Multi-Region and a copy in eu-west-1, five clusters per region, warm standby to pilot light, and MemoryDB snapshot in eu-west-1 every 15 minutes.
- Section 9: the stage row "2 regions", the prod row "3 AZ x 2 regions", and the EKS upgrade sequence "prod eu-west-1, then prod eu-central-1".
- Section 23.5: the prod MCP row naming eu-west-1 and eu-central-1.
- Section 1: the opening sentence ("two regions, eu-central-1 primary, eu-west-1 reserve").
