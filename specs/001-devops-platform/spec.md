---
id: 001-devops-platform
status: in-progress
owner: platform
milestone: 001-devops-platform
issue: "#22"
pci-impact: yes
adr: []
---

# 001-devops-platform: DevOps platform as code, from requirements to verified delivery

## Problem

The platform has one architecture document that lives outside the repository, and the work derived from it was split across two specifications and open-ended tickets: a requirements specification, a GitHub-settings specification and a build of infrastructure, charts, pipelines and observability that had no specification at all. Progress could not be read from the tracker, because tickets were wide and did not match the work in the repository.

This is the single specification of the DevOps part. It states the requirements (the SRS), and the work that implements them in seven milestones, each ticket being one task of `tasks.md` with a verifiable "Done when" list. The project is complete when every task is done, the pull request to `main` is merged by a human, and nothing remains in the tracker except follow-ups opened after the merge.

Milestones:

- M1 Requirements baseline: SRS of the DevOps part confirmed as the baseline (docs/requirements, ADR of the region model).
- M2 Repository as code: GitHub organization, repository, rulesets, environments and CODEOWNERS in Terraform; repository files; drift check.
- M3 Cloud foundation: State bootstrap, CI roles, AFT, network, edge, keys, secrets and registries for dev and stage.
- M4 Data stores and recovery: Aurora, DynamoDB, MemoryDB, MSK, OpenSearch, ClickHouse, backups and the recovery region.
- M5 Kubernetes platform and delivery: EKS, Karpenter, Helm charts, Argo CD, CI/CD workflows and the ARC runner pool.
- M6 Security, policy and observability: Policy as code, Vault and secrets, observability, trust and SCP hardening.
- M7 Verification and release readiness: Load, chaos, smoke and e2e tests, review follow-ups, placeholders, threat model.

## Goals and non-goals

Requirements (M1, the earlier requirements specification):

- Goal: write the first edition of the software requirements specification of the DevOps part in `docs/requirements/`, structured after ISO/IEC/IEEE 29148, in English, derived from the architecture document, and confirm it as the baseline through the spec gate.
- Goal: every requirement is one table row with a stable never reused ID (`FR-<area>-<n>`, `NFR-<area>-<n>`), one verification method and the technical implementation (tool, resource, setting or number); the text is purely technical, without introductions or explanation of trivial steps.
- Goal: every DevOps requirement of the architecture document appears in the SRS. Precedence on a conflict: the owner decisions below, then section 1 of the source, then the other sections; a contradiction that none of them settles is an open issue and never a requirement. `srs.md` lists every owner decision with the source passage it overrides, and every withdrawn source passage.
- Goal: `traceability.md` maps each in-scope section and subsection to requirement IDs, and each requirement back to a section.
- Goal: after the baseline is confirmed, any change to the SRS is an addendum (`docs/requirements/addenda/README.md`); addenda start only after the baseline has passed the spec gate, and an addendum that changes a requirement cited by an approved specification forces that specification to be re-validated first.
- Goal: Kubernetes resources and Helm charts have one exact place each: `deploy/` is laid out as in section 17 (`charts/`, `envs/`, `platform/`), with the per-chart placement of AC10.
- Non-goal: the business behavior of the payment services (PSP routing, merchant API authentication, webhook signing, routing of payments between cells by hash, card tokenization logic); sections 2 and 6 are in scope only for their platform controls.
- Non-goal: the repository process: section 11; in section 14 the directory tree, directory naming and the glossary extract; in section 18 the directory tree (including the layout of `infra/` and `policy/`), agent models, code comments and refactoring; sections 21.4 and 27.1 to 27.4, 27.7, 27.8; the Claude Code bullet of 21.5. `CLAUDE.md` governs them.
- Non-goal: design rationale and operating procedures (ADRs, runbooks); the SRS links to them as "ADR-0NN (architecture section 13)".
- Non-goal: translating the architecture document; the M1 tasks change no code, infrastructure or policy. The only architecture decision made here is the ADR of T10 that records the owner decisions D6 and D7.

Platform work (M2 to M7):

- Goal: every file the milestones list exists in the repository as code, validated offline by the checks named in the acceptance criteria, and delivered by one pull request from `feat/infra-code-all` to `main`.
- Goal: the tracker mirrors this specification: one GitHub issue per task, grouped by milestone, state Todo, In progress or Done, closed by the pull request that delivers it.
- Goal: placeholders (`CHANGEME`, `REPLACE_*`) are the only unknown values, and `tools/ci/placeholder_report.py` lists them.
- Non-goal (platform work): applying anything, and creating the AWS accounts, the GitHub organization, the GitHub App or any secret; the owner supplies real values.
- Non-goal (platform work): `prod` and `cde-prod` live stacks and values; agents may not write them (`.claude/orchestration.yaml`), a human adds them after the dev and stage stacks are verified.
- Non-goal (platform work): the business behavior of the payment services and changes under `vendor/`.

- D1, version tags: `v*` (SemVer `vX.Y.Z`; breaking change bumps major, `feat` bumps minor, `fix` bumps patch) replaces `rel-<date>.<N>`. Only the tagging workflow creates them, after a successful prod rollout in all cells; creation is allowed and deletion denied by the ruleset; a tag builds nothing and attaches a changelog, SBOM and provenance. The version identifier stays the image digest.
- D2, application databases (Aurora PostgreSQL of every cell and of the locker, DynamoDB with the merchant-to-cell map): a base backup plus point-in-time recovery to any second within the retention; data loss on restore at most 5 minutes; the restore is verified automatically every day; an alert fires when the latest restorable time lags more than 5 minutes for 10 minutes; a policy denies a stateful resource without a backup plan, the written exception list of section 19 being the only way around it. This replaces the weekly restore test and the retention and frequency rows of sections 5 and 19 for these stores.
- D3, other stores and schema changes: MemoryDB, ClickHouse and Velero are backed up once an hour (AWS Backup minimum for MemoryDB) with retention 35 days, replicated across AZs; critical payment data of MemoryDB is duplicated in Aurora within the drain lag SLO; MemoryDB has no point-in-time recovery, so its recovery rests on the multi-AZ log and on rebuilding from Aurora. Before every migration or schema change of any database (Aurora, DynamoDB, ClickHouse, OpenSearch) the migration Job takes an on-demand snapshot labelled with the change and starts the change only when the snapshot is `available`; that snapshot is kept 35 days.
- D4, restore speed: restoring an application database in Frankfurt after a logical error takes at most 30 minutes into prepared capacity (the loss of the working region is recovered by D7, not by a restore); `backup_restore_duration_seconds` is recorded per store with an alert at 80% of the target and a trend against data size. Recent copies stay in hot storage; managed backups (Aurora, DynamoDB, MemoryDB) are compressed by AWS, self-managed ones (ClickHouse, Vault, OpenSearch, Velero) use zstd at a low level so that decompression is fast, compressed before encryption, in parallel streams; restore traffic uses VPC endpoints for S3; the restore role, the KMS key access and the service quotas are prepared and exercised by the daily test; a restore is code (an automation document and Terraform) with no manual step except the approval of its pull request by two people; independent databases are restored in parallel; a restored PostgreSQL database is warmed (`pg_prewarm` of the hot tables) and takes traffic only after readiness.
- D5, storage tiers: backup copies stored as objects (S3-based backups of ClickHouse, Vault, OpenSearch, Velero and exports) move to a colder tier after 7 days and to a still colder tier after 14 days by lifecycle rules in Terraform; the monthly 7-year archive goes to the coldest tier; the restore targets apply to the hot tier, and the restore time of colder tiers is stated per tier. Continuous recovery of Aurora and DynamoDB and managed snapshots that AWS does not tier keep their native tier. AWS limits (for the Infrequent Access classes 30 days in the first tier) are checked at implementation and the days adjusted.
- D6, region model: Frankfurt (eu-central-1) is the only region that writes. High availability inside it comes from three AZs: Aurora quorum and reader promotion, MemoryDB multi-AZ, MSK RF 3, pod anti-affinity and PDB per AZ, and the writer of each cell in a different AZ. The platform has two regions: us-east-1 is the only recovery region and receives data and backups continuously. In prod it runs a hot standby at the working size (ADR-0019): per cell and for the spare an EKS cluster with the working-region node pools and workload floors, MemoryDB with the working shard count, and one Aurora instance per global secondary with the writer class of its working cluster, serving no requests while Frankfurt is healthy. Stage and dev run in eu-central-1 alone; their us-east-1 stacks are only the global CloudFront, WAF, ACM and KMS resources. There is no active-active. Detection by independent signals, fencing of Frankfurt and promotion are automatic, with a lock per cell, because a false switch with two writers can charge a payment twice. ADR-0019 supersedes ADR-0017, which replaced the eu-west-1 standby of ADR-004 and section 3.
- D7, data replication and the switch: in prod, Aurora of every cell, the spare and the locker has an Aurora Global Database secondary in us-east-1 with one instance that only reads until promotion, behind RDS Proxy; an alert fires when its lag exceeds 5 s and the RPO budget is 10 s; managed RPO (`rds.global_db_rpo`) stays off because it pauses commits in Frankfurt when the link is slow. DynamoDB uses Global Tables in MREC mode with a replica in us-east-1, written only from Frankfurt (IAM and an SCP deny writes there until the promotion). MemoryDB is not replicated across regions: hourly snapshots are copied to us-east-1, and after a promotion the running us-east-1 MemoryDB warms from Aurora, gated by D8; entries not yet drained are lost (at most the drain lag, p99 5 s) and their payments are settled by `sync` with the PSP. Accepted risk (owner decision): a repeated request after the switch, with the same idempotency key, could create a second charge if the key was still in MemoryDB and not yet in Aurora (at most the drain lag, p99 5 s before the failure); the write-behind rule stays, and such a charge is detected by the PSP reconciliation over the 5-minute window with the reference id and refunded. MSK is not replicated: the payment path accepts payments without MSK, events reach S3 through the S3 sink, and Kafka is rebuilt from that archive and ClickHouse is restored from its hourly backup and caught up from it. S3 (backups, audit logs, Terraform state, archives) is replicated to us-east-1 with Replication Time Control (15 minutes) and Object Lock on every copy; hourly snapshot copies of Aurora, DynamoDB, MemoryDB, ClickHouse, Vault and Velero go there; container images and charts are replicated by ECR replication. Also in us-east-1 all the time: the VPC with its own egress path, Network Firewall policy, egress Elastic IPs registered with every PSP, VPC endpoints, KMS multi-Region replica keys, IAM roles, Secrets Manager replicas, `edge-dns-routing` and `dr-failover`. The monitoring that confirms the switch runs from three independent points outside eu-central-1. The prod us-east-1 VPC CIDR is 10.151.0.0/16 in `config/platform.yaml` (`network`), which does not overlap Frankfurt. The switch builds and scales nothing; its timed critical path is 32 minutes: detection and confirmation 10, fencing 2, Aurora promotion 3, cache warm-up 15, traffic switch 2; the RTO target is 60 minutes. It is measured in prod by a quarterly announced game day with on-call approval, followed by the switch back; stage exercises the component steps. RPO: payment data at most 10 s (Aurora) plus undrained entries within the drain lag, with charges confirmed by PSPs recovered by reconciliation; DynamoDB seconds; S3 and the event archive 15 min; snapshot-only stores (MemoryDB, ClickHouse, Vault, Velero) 1 h; Kubernetes state 0 because Git is the source. The promotion of the Aurora secondary is the point of no return and happens under a lock per cell.
- D8, cache warm-up (an owner addition that the source does not contain): after a node replacement, an AZ loss or a recovery a cell takes traffic when at least 75% of the most important hot keys (merchant configuration, routing, limits), loaded by priority, are in MemoryDB, measured by `cache_warm_ratio`; the rest of the cache warms under traffic. The readiness probe waits at most 5 minutes; if the ratio is still below 75% the cell takes traffic anyway and raises an alert that does not page the on-call.

## Acceptance criteria

Every criterion names the check that proves it.

M1 Requirements baseline (tasks T1 to T10):

Every criterion names the check that proves it.

- [ ] AC1: `docs/requirements/` contains `srs.md`, `nfr.md`, `infrastructure.md`, `data-and-recovery.md`, `security-and-access.md`, `delivery.md`, `policy-and-cost.md`, `observability-and-testing.md` and `traceability.md`; verified by `ls docs/requirements`.
- [ ] AC2: every requirement ID matches `^(FR|NFR)-[A-Z]+-[0-9]+$` and is defined exactly once across all files; `NFR-` IDs are defined only in `nfr.md` and the other files cite them; verified by `tools/lint/srs-lint` exiting 0 and a search showing no `NFR-` definition outside `nfr.md`.
- [ ] AC3: every requirement is one "shall" statement of at most 400 characters with exactly one verification method (test, metric, inspection, analysis or demonstration) and an implementation of at most 300 characters; verified by `tools/lint/srs-lint` exiting 0 and by the human reviewer for compound statements.
- [ ] AC4: `nfr.md` holds these values identical to the source (decimal normalization 99,99% to 99.99% and 1 430 to 1,430) or to the owner decision that overrides it:
  - load model, section 1: 160, 480, 1,430 and 2,860 TPS with about 1,100, 3,300, 10,000 and 20,000 RPS, 13.8 million payments a day, 7 API calls, 50 IOPS and 16 KB per payment;
  - SLOs, section 1: 99.99% with budget 4.3 min; p99 under 150 ms for 99.9% of requests with budget 43.2 min; p99 under 50 ms and 99.95% with budget 21.6 min; webhook delivery under 60 s at 99.9% with no budget, and the SLI exclusion (declines by the issuer and PSP errors correctly passed on or rerouted do not count);
  - RTO and RPO per store, taken from D7 and from the rows of section 1 that survive D6 (AZ loss 0 and 1 min): payment data RPO 10 s plus the drain lag (p99 5 s), RTO 60 min; locker RPO 10 s, RTO 60 min (replaces the row 0 and 5 min); DynamoDB about 1 s; S3 and the event archive 15 min plus the S3 sink flush interval; ClickHouse restored from its hourly backup and caught up from the event archive, RPO 15 min and RTO 4 h as in section 1; Vault and Velero 1 h; Kubernetes manifests 0 (Git) and cluster objects 1 h; the PSP reconciliation window is 5 minutes, sized to the payment-data RPO (10 s plus the drain lag plus a margin), and one hour only in the snapshot-copy fallback of D7;
  - sections 2 and 13: drain lag SLO p99 under 5 s with the alert at stream length above 50,000; locker SLO 99.99%;
  - section 12 limits: an Infracost increase above 1,000 USD a month needs FinOps approval, AWS Budgets alerts at 80% and 100%, reservation utilization above 95%, coverage 70 to 80%, Savings Plan at 80% of the minimum hourly compute; the estimate of about 105,000 USD a month is context, not a requirement;
  - sections 25.2 and 25.4: the per-layer alert coverage and fire-drill coverage targets;
  - owner decisions: data loss 5 min, latest restorable time alert at 5 min for 10 min, restore 30 min with the 80% alert, retention 35 days, hourly backups, colder tiers at 7 and 14 days, warm-up 75% of the priority keys within 5 min, the Aurora lag alert at 5 s and RPO budget 10 s, the RTO budget of D7, us-east-1 as the only recovery region with continuous replicas and, in prod, a hot standby at the working size (ADR-0019);
  - verified by `grep` of each value in `nfr.md` and a comparison by the human reviewer.
- [ ] AC5: `traceability.md` has one row per numbered subsection of every in-scope section that has subsections (and one per unnumbered part of sections 1 and 8), one row per other in-scope section, one row per ADR of section 13 (IDs or "design decision only"), and an "out of scope" row with the reason for each excluded part; verified against the architecture headings and by `tools/lint/srs-lint`, which fails if a defined ID is missing from `traceability.md` or a cited ID is not defined.
- [ ] AC6: the documents use glossary terms and contain no Cyrillic; every `/glossary-check` warning is fixed or justified in the list of terms used in another sense in `srs.md`; verified by `/glossary-check` and by `LC_ALL=C.UTF-8 grep -rP '[\x{0400}-\x{04FF}]' docs/requirements` printing nothing.
- [ ] AC7: no requirement contradicts the architecture document except where an owner decision listed in `srs.md` overrides it, and none describes business behavior of the payment services; verified by the human reviewer of the pull request.
- [ ] AC8: every file in `docs/requirements/` outside `README.md` and `addenda/` has `status: baseline`, and the commit that sets it passes the spec gate with `Spec: specs/001-devops-platform#T9`; verified by `tools/lint/spec-gate` on that commit, and by the gate rejecting an addendum before this commit exists.
- [ ] AC9: no filler: no requirement or implementation exceeds the limits of AC3, no section explains a step an engineer or agent already knows, and the human reviewer finds no filler; verified by `tools/lint/srs-lint` and the human reviewer of the pull request.
- [ ] AC10: `infrastructure.md` fixes the `deploy/` layout and the per-chart placement (one file per resource kind in `templates/`, tests in `tests/`, schema and values next to `Chart.yaml`, environment values only under `envs/<env>/[<region>/[<cell>/]]`, addons only under `platform/`) and states that every Kubernetes manifest lives under `deploy/`; verified by the human reviewer.
- [ ] AC11: `srs.md` lists D1 to D8 with the source passage each overrides, and the withdrawn passages: MemoryDB Multi-Region, Velero, S3 and Terraform-state copies to eu-west-1, the cde-prod eu-west-1 VPC, clusters in each region, the eu-west-1 endpoint group of Global Accelerator (ADR-007), the 5-minute PSP reconciliation after failover, the S3 audit copy target in eu-west-1 (the audit copy now goes to us-east-1), eu-west-1 in the SCP region allow list, MirrorMaker 2 of section 19, the quarterly full restore of a cell in the DR region of section 19, the 5-minute RTO derivation of section 3 and the pilot-light rationale of ADR-004, and the locker row RPO 0 and RTO 5 min of section 1, and the replicas "in the reserve region" of ADR-003 and ADR-013; verified by the human reviewer.
- [ ] AC12: `docs/adr/` contains the ADR of T10 that records the region model of D6 and D7 and supersedes ADR-004, and ADR-0019 that supersedes it with two regions and a prod hot standby in us-east-1; verified by `ls docs/adr`.

M2 Repository as code (T11 to T16):

- [ ] AC13: `infra/github/` holds only `main.tf`, `variables.tf`, `versions.tf`, `backend.hcl.example`, `config/owners.yaml`, `README.md` and `modules/{organization,repository,rulesets,environments,codeowners}/`, each module with `main.tf`, `variables.tf`, `versions.tf` and `tests/`; verified by `ls` and `tools/lint/structure`.
- [ ] AC14: every variable that names a real object has a `CHANGEME` default, no secret is in the repository and the GitHub App key is read from `GITHUB_APP_PEM_FILE`; verified by `gitleaks detect` and `terraform validate`.
- [ ] AC15: `terraform fmt -check`, `validate`, `tflint` and `terraform test` (mocked provider) pass in `infra/github/` and assert each row of architecture section 10: squash-merge only, auto-delete, 2 approvals with 1 from CODEOWNERS, dismiss stale, last-push approval, required checks, linear history, signed commits, merge queue, no force push, `v*` tag rule, environment reviewers, read-only `GITHUB_TOKEN`, SHA-pinned allowlisted actions.
- [ ] AC16: `CODEOWNERS` exists, is generated from `infra/github/config/owners.yaml` and has one line per mapping; CDE paths need two approvals from the owning teams; verified by a `terraform test` assertion.
- [ ] AC17: the drift workflow, `renovate.json5`, `.pre-commit-config.yaml` and `commitlint.config.js` are valid for their tools and `spec-gate` runs at the `commit-msg` stage; verified by `actionlint`, `pre-commit validate-config`, `renovate-config-validator` and `commitlint --print-config`.
- [ ] AC18: `commitlint` and `tools/lint/spec-gate` accept and reject the same subjects; verified by the parity test of T16.

M3 and M4 Cloud foundation, data stores and recovery (T17 to T23):

- [ ] AC19: every module under `infra/modules/` has `versions.tf`, `variables.tf`, `main.tf`, `outputs.tf`, a README of at most 10 lines and `tests/`, and passes `make lint-terraform test-terraform`.
- [ ] AC20: dev and stage stacks use variables for every account, role and CIDR; `mock_outputs` are allowed only for `init` and `validate`; verified by `terragrunt validate` and `tools/ci/placeholder_report.py`.
- [ ] AC21: in prod, Aurora of every cell, the spare and the locker has a Global Database secondary in us-east-1, DynamoDB uses Global Tables with writes denied in us-east-1 until a promotion, and backups keep 35 days with colder tiers at 7 and 14 days; verified by `terraform test` assertions.

M5 Kubernetes platform and delivery (T24 to T30):

- [ ] AC22: `make lint-helm test-helm` pass; every image is referenced by digest and every chart has `values.schema.json`, `ci/lint-values.yaml` and `tests/`.
- [ ] AC23: workflows pass `actionlint`, pin every action by SHA, set `permissions: {}` at the top and push images only from `main` and `release/*`; the CI job `ci-gate` is green on the pull request.
- [ ] AC24: the locker Aurora admits only the locker pod security groups, and `ci-pr` runners have no route to cell or CDE namespaces; verified by `terraform test` and the NetworkPolicy test.

M6 and M7 Security, observability and verification (T31 to T40):

- [ ] AC25: `make test-policy` passes; `python3 observability/tests/run.py` passes and every alert has a runbook file.
- [ ] AC26: OIDC trust of the apply roles is limited to `main` and `release/*`, and the `terraform-apply` SCP exception names an exact ARN; verified by tests with a negative case.
- [ ] AC27: k6, chaos, smoke, e2e and contract suites run offline in CI; prod Argo CD Applications do not auto-sync from `main`; the threat model covers the `ci-pr` perimeter; no `REPLACE_*` remains for an environment before its apply.

## Impact on SLO, PCI and cost

- SLO: none while nothing is applied; the SRS records the SLOs and D6 and D7 change the region rows of section 1.
- PCI: yes, tasks T25, T29 and T30 touch the CDE paths `infra/live/*/*/locker/**` and `deploy/platform/arc/**`; the recovery region of D2 to D7 brings encrypted card data of the locker into backups, KMS replica keys, IAM roles and the SCP allow list, so the pull request carries `PCI-Impact: yes` commits and its own PCI review.
- Cost: none now; the daily restores, hourly backups, 35-day retention, S3 replication and CI runner pools add cost to be estimated with Infracost before the first apply.

## Risks

- The architecture document is the only source and sits outside the repository, so the SRS could drift from it. Mitigation: the source path, date and checksum prefix are pinned in `plan.md` and `srs.md`, AC4 and AC5 are checked against it, and `traceability.md` names the section of every requirement.
- Numbers can be mistyped. Mitigation: AC4 lists every value and a reviewer compares them.
- Requirements, design and procedures are easy to mix. Mitigation: the non-goals name what stays out, each requirement is one "shall" statement, and the human reviewer signs off AC7.
- Many owner decisions override the source, so writers could carry over stale text. Mitigation: AC11 lists the overridden and withdrawn passages and T3, T4 and T7 cite that list.
- D7 keeps the prod us-east-1 standby at the working size all the time: it is about 37% of the prod bill (`docs/architecture/cost/prod.md`), a drift between the regions shows up only at a switch unless the game day and Argo CD sync status catch it first, and two regions leave no fallback if us-east-1 is lost together with Frankfurt. Mitigation: commitments cover the standby like the working region, deploys and upgrades apply to both regions, and the review conditions of ADR-0019.
- GitHub issues do not exist yet: they are created after the approval, and until then `issue: none`. Mitigation: the spec gate rejects a commit for a task without an issue number.
- The build was written before this specification (owner-directed, commits carry `Spec: none`); the tasks describe it after the fact and the "Done" state means implemented and delivered by the pull request, not applied.
- One large pull request (about 60 commits) is hard to review; mitigation: the milestones group the diff by concern and the Sonnet review findings are tracked as T34, T35 and T38.
