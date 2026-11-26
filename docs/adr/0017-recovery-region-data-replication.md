---
status: accepted
date: 2026-11-26
supersedes: [ADR-004, "ADR-015 (confirmation step)"]
requirements: [FR-INF-12, FR-INF-13, FR-INF-14, FR-INF-15, FR-INF-16, FR-INF-17, FR-DAT-18, FR-DAT-25, FR-DAT-26, NFR-REC-2, NFR-REC-3, NFR-REC-18, NFR-REC-19, NFR-REC-20]
---

# ADR-0017: region model, data replicated to two recovery regions, warm standby in us-east-1

## Context

- Frankfurt (eu-central-1) is the only region that may write payment data: two writers can charge a payment twice, and payment writes cannot be merged by last-writer-wins (owner decision D6).
- Loss of the working region must be recovered within the RTO of 60 min (75 min in plan B) and the payment-data RPO of 10 s plus the drain lag (D7, `NFR-REC-2`, `NFR-REC-3`).
- ADR-004 chose a warm standby in eu-west-1 sized for an RTO of 5 min; D6 and D7 removed eu-west-1 and moved recovery to us-east-1 and us-east-2.
- A recovery region that holds only data must create EKS, nodes, Aurora instances and MemoryDB at the switch; that is the longest part of the RTO and depends on free AWS capacity at that moment.

## Options considered

1. Active-active in two regions: rejected; payment writes in two regions conflict and the write-behind path has no merge rule.
2. Data-only recovery regions, all compute created from Terraform at the switch, semi-automatic switch with one on-call confirmation (D6, D7 as first written): lowest cost, but the critical path of about 54 min is spent creating compute, and the confirmation adds detection time.
3. Warm standby in us-east-1 with automatic data promotion, us-east-2 as data-only plan B: compute already runs in us-east-1, so the switch is promotion and traffic shift; us-east-2 keeps a second copy of the data in case us-east-1 cannot take over.

## Decision

Option 3, as implemented in `infra/live/<env>/{eu-central-1,us-east-1,us-east-2}`:

- eu-central-1 is the only writing region; high availability inside it comes from three AZs (`FR-INF-11`). No active-active.
- Data replicates asynchronously to us-east-1 and us-east-2: Aurora Global Database for every cell and the locker (`rds.global_db_rpo` off), DynamoDB Global Tables in MREC mode with writes denied in both recovery regions, S3 with Replication Time Control and Object Lock, AWS Backup copies, Secrets Manager and ECR replicas, multi-Region KMS keys (`FR-DAT-18`, `FR-INF-19`).
- us-east-1 is a warm standby where `standby.enabled` is set (stage and prod): per cell EKS, capped Karpenter pools, MemoryDB and one Aurora reader on the local secondary, its own egress VPC, Network Firewall and transit gateway (`FR-INF-6`, `FR-INF-13`). It runs the same image digests against its own replicated data and receives no requests while Frankfurt is healthy; its database endpoints are the local secondaries, so promotion changes no values.
- Traffic: Route 53 failover records with HTTPS health checks; Frankfurt is primary and serves all traffic while its check passes, us-east-1 is answered only when it fails (`infra/modules/dns-routing`, `FR-INF-15`).
- Promotion is automatic and replaces the confirmation step of ADR-015: after 5 consecutive failing one-minute periods of the Frankfurt health check, the alarm starts `scripts/dr/failover.py --auto` through `infra/modules/dr-failover`. Per cell and for the locker it fences Frankfurt by a drop rule in its `psp-fence` rule group as far as Frankfurt answers, runs `failover-global-cluster`, and removes us-east-1 from the DynamoDB write deny. A DynamoDB lock per cell and one concurrent run prevent a second promotion; missing health-check data never starts it (`NFR-REC-19`, `FR-INF-17`, `FR-DAT-26`).
- us-east-2 holds only non-compute resources and headless Aurora secondaries. When us-east-1 cannot take over, compute is created in us-east-2 from the same Terraform and Terragrunt code after 10 minutes without capacity in us-east-1 (plan B, `NFR-REC-18`), with node pools over several instance families and both architectures (`FR-INF-16`).
- MemoryDB and MSK are not replicated across regions: MemoryDB is rebuilt from Aurora behind the 75% warm-up gate of D8, Kafka from the S3 event archive.
- Failback is planned, never started by an alarm, needs a named approver (`--confirmed-by`) and refuses while the lag to Frankfurt exceeds 1 s (`NFR-REC-20`).
- Payments charged at a PSP in the 5-minute window before promotion and missing in the promoted database are found by `OrphanPaymentWebhooks` and reconciliation and refunded by people (`NFR-REC-10`).

## Cost

- Standby compute and readers in us-east-1 for stage and prod: per cell capped node pools (`payments` 40, `stateful` 20, `cde` 20, `workers` 20 vCPU) and one `db.r7g.4xlarge` reader, plus MemoryDB, a second egress path and transit gateway.
- Storage and transfer of a second full data copy in us-east-2.
- An automatic promotion can follow a false failure signal; the 5 consecutive failing minutes, the fencing and the per-cell lock limit that risk, and Aurora keeps the old writer from rejoining as a writer.
- Data in us-east-1 lags by the replication lag; that lag is the data loss of a failover (`AuroraGlobalLagHigh` at 5 s, budget 10 s).

## Review condition

Review when any of these holds:

- the quarterly region switch (`tests/chaos/region-switch/`) exceeds the RTO of `NFR-REC-3` or leaves more than one writer;
- an automatic promotion starts without a confirmed loss of Frankfurt;
- the spend of the us-east-1 standby on the FinOps dashboard exceeds the budget the FinOps owner sets for it;
- a merchant requires data processing in a region other than eu-central-1 (then merchants are sharded by region).

## Links

- Owner decisions D6, D7, D8 in `docs/requirements/srs.md`; superseded: ADR-004 (warm standby in eu-west-1), the one-confirmation switch of ADR-015 (section 21.2).
- Runbook: `docs/runbooks/meta/promote-standby-region.md`.
