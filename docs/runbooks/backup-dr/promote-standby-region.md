# PromoteStandbyRegion

Layer backup-dr, service aurora, severity critical, owner data-platform-oncall.

## Symptom

The Route 53 health check of the Frankfurt ingress fails and DNS answers with the us-east-1 standby. The standby databases are still read-only secondaries until promoted, so writes fail until step 2 is done.

## Diagnostics

1. Confirm the Frankfurt outage with `RegionDown` (two of three probe points); a single failing probe point is not an outage.
2. Check the replication lag per cell and for the locker (`AuroraGlobalLagHigh`) to estimate the data that would be lost on promotion.
3. Check that the us-east-1 clusters, readers and MemoryDB are healthy.

## Actions

Promotion starts by itself: when the Route 53 health check of the Frankfurt ingress fails for five minutes, the alarm `*-working-region-down` invokes the Lambda of `infra/modules/dr-failover` (`scripts/dr/failover.py --mode warm --auto`). For every cell and the locker it fences what is reachable, runs `failover-global-cluster` on the Aurora global cluster, and removes us-east-1 from the DynamoDB deny-write policy. A lock record per cell prevents a second promotion. Route 53 has already moved the traffic.

1. Check the Lambda log (`failover-finished` with a result per cell). Exit code 3 means another run holds the lock, which is not a failure.
2. If a cell failed, re-run it: invoke the Lambda again with the same alarm event (the run id is the incident time, so the run resumes) or run `scripts/dr/failover.py --mode warm --auto --cell <cell> ...` by hand through `runbook-actions`.
3. The standby releases already use the local cluster endpoints, which become writers on promotion; no values change. Enable migrations (`migrations.enabled`) only after the writer is stable and a migration is due.
4. `fence-unverified` in the log means Frankfurt's control plane did not answer; Aurora keeps the old writer from rejoining as a writer, but check the PSP fence rule group once Frankfurt is reachable.

Failing back is a planned switch in the opposite direction after Frankfurt is rebuilt from the replicated data; do not fail back during the incident.

## Escalation

The incident commander is added at once; the promotion itself needs no confirmation. Default chain: primary acknowledges within 5 min, the secondary is paged at 5 min and the incident commander at 15 min (section 20.6).
