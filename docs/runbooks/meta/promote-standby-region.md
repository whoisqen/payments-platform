# PromoteStandbyRegion

Layer meta (a procedure that no alert points to), service aurora, owner data-platform-oncall.

## Symptom

The Route 53 health check of the Frankfurt ingress fails. us-east-1 is the prod hot standby: its clusters, services and MemoryDB run at full size, and each Aurora global cluster has an instance there, read-only until promotion. Writes fail until the promotion is done; DNS moves to us-east-1 once its ingress passes its health check.

## Diagnostics

1. Confirm the Frankfurt outage with `RegionDown` (two of three probe points); a single failing probe point is not an outage.
2. Check the replication lag per cell and for the locker (`AuroraGlobalLagHigh`) to estimate the data that would be lost on promotion.
3. Check that the us-east-1 cells are healthy: Argo CD shows their Applications Synced and Healthy, and the `use1` probe point is green.

## Actions

Promotion starts by itself: when the Route 53 health check of the Frankfurt ingress fails for five minutes, the alarm `*-working-region-down` invokes the Lambda of `infra/modules/dr-failover` (`scripts/dr/failover.py --auto`). For every cell and the locker it appends a drop rule to the `psp-fence` rule group of the working region when that region answers (best effort), runs `failover-global-cluster` on the Aurora global cluster, and removes us-east-1 from the DynamoDB deny-write policy. A lock record per cell prevents a second promotion. Route 53 then moves the traffic to the running us-east-1 cells.

1. Check the Lambda log (`failover-finished` with a result per cell). Exit code 3 means another run holds the lock, which is not a failure.
2. If a cell failed, re-run it: invoke the Lambda again with the same alarm event (the run id is the incident time, so the run resumes) or run `scripts/dr/failover.py --cell <cell> --confirmed-by <approver> ...` by hand.
3. The standby releases already use the local cluster endpoints, which become writers on promotion; no values change. Enable migrations (`migrations.enabled`) only after the writer is stable and a migration is due.
4. The log event `reconcile-window` gives the five minutes before the promotion. Charges made at the PSP in that window may be missing from the promoted database; the alert `OrphanPaymentWebhooks` shows them as PSP webhooks for unknown payments (`docs/runbooks/application/warnings.md#orphan-payment-webhooks`). Refunds are decided by people, never automatic.
5. `fence-unverified` in the log means Frankfurt's control plane did not answer; Aurora keeps the old writer from rejoining as a writer, but once Frankfurt is reachable, add the drop rule to `psp-fence` by hand or run the script again.

## Failback

Planned, never during the incident, and only after Frankfurt is rebuilt and rejoined the Aurora global clusters as a replicating secondary. A person or an agent runs it after a human approves:

`scripts/dr/failover.py --mode failback --cell <cell> --confirmed-by <approver> --name-prefix <prefix> --env <env> --source-region <working> --target-region <standby> --deny-policy-arn <arn>`

Per cell and the locker it refuses unless the replication lag to Frankfurt is at most 1 s, then switches Aurora over without data loss, restores the DynamoDB deny-write policy version saved at the failover, removes the drop rule from `psp-fence` and releases the lock. Without `--confirmed-by` it refuses; it is never started by an alarm.

## Escalation

The incident commander is added at once; the promotion itself needs no confirmation. Default chain: primary acknowledges within 5 min, the secondary is paged at 5 min and the incident commander at 15 min (section 20.6).
