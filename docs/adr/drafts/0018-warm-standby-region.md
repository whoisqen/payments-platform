# ADR 0018: warm standby in us-east-1

Status: draft. Replaces the "no compute in recovery regions" part of D6 and D7 (the cold recovery model of the region ADR in `specs/001-devops-platform` T10).

## Context

The recovery regions held only data and prepared networks; all compute was created at the switch. That costs about an hour of RTO and gives clients far from Frankfurt no faster path.

## Decision

- eu-central-1 stays the only writing region. There is no active-active.
- us-east-1 is a warm standby that runs: per cell a cluster, Karpenter pools, MemoryDB and Aurora reader instances. Replication between regions is asynchronous (Aurora Global Database, DynamoDB Global Tables).
- Route 53 failover records with HTTPS health checks (`infra/modules/dns-routing`): Frankfurt is PRIMARY and serves 100% of traffic while its check passes; us-east-1 is SECONDARY and is answered only when the Frankfurt check fails. No traffic is split between regions in normal operation.
- The standby runs the same releases against its own replicated data and receives no requests while Frankfurt is healthy. Its database endpoints are the local Aurora secondaries, so promotion (`docs/runbooks/meta/promote-standby-region.md`) changes no deploy values.
- Each region has its own egress path (egress VPC, Network Firewall, transit gateway) so PSP traffic never crosses regions.
- Data is replicated asynchronously to the standby: Aurora Global Database, DynamoDB Global Tables, S3 replication of backup and archive buckets, Backup copy jobs to the recovery vaults, Secrets Manager and ECR replicas, multi-Region KMS keys.
- Promotion of the us-east-1 data stores is automatic (owner decision, replaces the semi-automatic switch of D6): the failed Route 53 health check of Frankfurt starts `scripts/dr/failover.py --auto` through `infra/modules/dr-failover`. Safeguards: five consecutive failing minutes, missing data never triggers, a DynamoDB lock per cell, one concurrent run, and fencing (a drop rule in the `psp-fence` Network Firewall group) as far as the failed region answers. Aurora itself keeps the old writer from rejoining as a writer.
- us-east-2 stays data and backups only; plan B of D7 is unchanged.
- Environments opt in with `standby_enabled` in `env.hcl` (stage); dev has no standby.

## Consequences

- Data in us-east-1 lags by the replication lag (alert at 5 s); that lag is the data loss window of a failover.
- Standby compute and readers add cost in stage and prod; Infracost must estimate it before the first apply.
- The switch runbook shrinks to promotion and traffic shift; the compute creation steps and the 60 minute RTO budget of D7 need a new calculation.
