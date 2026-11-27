---
status: accepted
date: 2026-11-27
supersedes: [ADR-0017]
requirements: [FR-INF-12, FR-INF-13, FR-INF-14, FR-INF-15, FR-INF-16, FR-INF-17, FR-DAT-18, FR-DAT-25, FR-DAT-26, FR-COST-4, NFR-REC-2, NFR-REC-3, NFR-REC-18, NFR-REC-19, NFR-REC-20, NFR-REC-21]
---

# ADR-0019: two regions, hot standby in us-east-1

## Context

- ADR-0017 used three regions. Frankfurt (eu-central-1) did the writing, us-east-1 ran a warm standby with capped node pools and one `db.r7g.4xlarge` reader per cluster, and a second recovery region held data only, as a fallback for when us-east-1 had no capacity.
- The FinOps audit (`docs/architecture/cost/audit.md`, finding 2) proposed removing the standby compute and building it at the switch (a pilot light). That saves 33,916 USD/month on demand in prod. The cost is that the RTO then depends on building EKS, MemoryDB and Aurora writers in us-east-1 during the incident.
- The owner requires us-east-1 to take the whole prod load at any moment. A standby that must first be built or scaled up does not meet that.
- Owner decisions D6 and D7 limit the platform to two regions: eu-central-1 writes and us-east-1 is the only standby. Only prod has a standby region. Stage and dev run in eu-central-1 alone.
- The targets stay the same: RTO 60 minutes, and a payment-data RPO of the Aurora Global lag (budget 10 s) plus the drain lag (`NFR-REC-2`, `NFR-REC-3`).

## Options considered

1. **Hot standby.** us-east-1 runs the prod cells at the working size all the time: the same clusters, node pools, replicas and MemoryDB, plus one Aurora instance per global secondary with the writer class of its working cluster. The switch fences Frankfurt, promotes Aurora, warms the cache and moves traffic. Nothing is built or scaled.
2. **Warm standby (ADR-0017).** us-east-1 runs at a reduced size: capped node pools and smaller readers. At the switch the readers are promoted, and Karpenter and the HPAs scale to full size. It costs less, but it cannot take the whole load at the moment of the switch. Scaling out also depends on free capacity in us-east-1 during a regional incident.
3. **Pilot light (audit finding 2).** Data replicas run all the time. The failover builds the clusters, node pools, workload IAM and MemoryDB, and adds an Aurora writer to each headless secondary. This is the cheapest option. Its timed critical path was 54 of the 60 minutes, and it depends on EC2 and MemoryDB capacity in us-east-1 during the incident.
4. **A second recovery region as a capacity fallback.** This keeps a data-only copy in another US region for when us-east-1 cannot supply capacity. With a hot standby, the switch needs no new capacity, so the fallback protects against nothing that remains. It costs 3,354 USD/month on demand across the environments.

## Decision

Option 1, for prod only. Options 2 and 3 are rejected because the owner requires the standby to be ready at any moment. Option 4 is rejected and the second recovery region is removed.

- us-east-1 runs per cell and for the spare: the EKS cluster with the working-region node pools, the workloads at their working-region floors, and MemoryDB with 2 shards of 3 nodes (1 shard for the spare). `standby.compute_enabled: true` in `config/environments/prod.yaml`.
- Each Aurora global secondary (cells, spare, locker) has one instance with the writer class of its working cluster, behind RDS Proxy. Until promotion the instance only reads.
- Also always running in us-east-1: DynamoDB Global Tables replicas, S3 replicas, AWS Backup copies, Secrets Manager, ECR and KMS replicas, the VPC with its own egress path, `edge-dns-routing` and `dr-failover`.
- The switch steps are detection and confirmation, fencing, Aurora promotion (the only point of no return), the cache warm-up gate of D8, and the traffic move by Global Accelerator and Route 53. MemoryDB is not replicated across regions. The us-east-1 MemoryDB is running but cold, so it warms from Aurora before a cell takes traffic. The timed scenario `tests/chaos/region-switch/scenario.json` has a critical path of 32 minutes against the 60-minute RTO.
- Detection, fencing, the lock per cell, automatic promotion, the 5-minute reconciliation window and the failback rules of ADR-0017 stay as they are.
- The compute-build and writer steps of `scripts/dr/failover.py` stay as a fallback for a standby that has lost its compute. `add_writer` skips a secondary that already has an instance. The build runs only when the `compute_build` input of `dr-failover` is set.
- The switch is exercised in prod as a planned, announced game day with on-call approval, followed by the switch back. Stage has no standby region and exercises only the component steps.

## Cost

- The prod us-east-1 lines come to 54,822 USD/month on demand, about 37% of the prod bill (`docs/architecture/cost/prod.md`). With the logs and security lines the standby adds, the hot standby costs 52,201 USD/month on demand (41,015 committed) more than the pilot light, and 18,285 more than the warm standby of ADR-0017.
- Removing the second recovery region saves 3,354 USD/month on demand. Running stage in eu-central-1 alone saves its standby and copies.
- The standby compute serves no requests while Frankfurt is healthy. Commitments (Compute and Database Savings Plans, MemoryDB reserved nodes) cover it like the working region.
- Deploys, upgrades and capacity changes apply to both regions. A drift between them shows up only at a switch, unless the game day and Argo CD sync status catch it first.
- Two regions leave no fallback if us-east-1 is lost together with Frankfurt.

## Review condition

Review when any of these holds:

- a prod game day exceeds the 60-minute RTO of `NFR-REC-3`, or its critical path exceeds 32 minutes in two game days in a row;
- the us-east-1 standby drifts from the working size (node pools, MemoryDB shards or Aurora classes) for more than one release;
- an automatic promotion starts without a confirmed loss of Frankfurt;
- the owner relaxes the requirement that the standby takes the whole load at any moment;
- the us-east-1 standby exceeds 40% of the prod bill;
- a merchant requires data processing in a region other than eu-central-1.

## Links

- Superseded: ADR-0017 (warm standby in us-east-1, second recovery region). The rest of its promotion, fencing and failback rules stays and is restated above.
- Owner decisions D6, D7 and D8 in `docs/requirements/srs.md`, with addendum `docs/requirements/addenda/001-two-regions-finops.md`. Cost basis: `docs/architecture/cost/audit.md`.
- Disaster recovery: [README](../dr/README.md), [failover](../dr/failover.md) and [drills](../dr/drills.md).
