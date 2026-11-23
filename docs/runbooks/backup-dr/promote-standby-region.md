# PromoteStandbyRegion

Layer backup-dr, service aurora, severity critical, owner data-platform-oncall.

## Symptom

The Route 53 health check of the Frankfurt ingress fails and DNS answers with the us-east-1 standby. The standby serves reads; writes still go to the Frankfurt writer, so they fail while Frankfurt is down.

## Diagnostics

1. Confirm the Frankfurt outage with `RegionDown` (two of three probe points); a single failing probe point is not an outage.
2. Check the replication lag per cell and for the locker (`AuroraGlobalLagHigh`) to estimate the data that would be lost on promotion.
3. Check that the us-east-1 clusters, readers and MemoryDB are healthy.

## Actions

1. Fence Frankfurt first (SSM document `pay-runbook-region-down` does this); two writers can charge a payment twice.
2. Promote the us-east-1 Aurora secondary of each cell and of the locker (global cluster failover), one cell at a time starting with `spare`.
3. Point the standby releases at the local writer: set the master database hosts in `deploy/envs/<env>/us-east-1/<cell>/values.yaml` to the promoted cluster endpoint and enable migrations only after the writer is stable.
4. Switch the DynamoDB deny-write regions (`deny_write_regions` of the dynamodb stack) so that us-east-1 may write.
5. Traffic needs no change: Route 53 already answers with us-east-1.

Failing back is a planned switch in the opposite direction after Frankfurt is rebuilt from the replicated data; do not fail back during the incident.

## Escalation

Promotion needs the incident commander and the primary on-call (ADR-015). Default chain: primary acknowledges within 5 min, the secondary is paged at 5 min and the incident commander at 15 min (section 20.6).
