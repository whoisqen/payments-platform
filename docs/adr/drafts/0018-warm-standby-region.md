# ADR 0018: warm standby in us-east-1

Status: draft. Replaces the "no compute in recovery regions" part of D6 and D7 (the cold recovery model of the region ADR in `specs/001-devops-platform` T10).

## Context

The recovery regions held only data and prepared networks; all compute was created at the switch. That costs about an hour of RTO and gives clients far from Frankfurt no faster path.

## Decision

- eu-central-1 stays the only writing region. There is no active-active.
- us-east-1 is a warm standby that runs: per cell a cluster, Karpenter pools, MemoryDB and Aurora reader instances. Replication between regions is asynchronous (Aurora Global Database, DynamoDB Global Tables).
- Route 53 latency records with HTTPS health checks (`infra/modules/dns-routing`) send clients to the nearer healthy region. An unhealthy region drops out of the answer, which is the failover.
- Reads are served locally in us-east-1. Writes are proxied to Frankfurt at application level.
- Promotion of the us-east-1 Aurora secondary stays semi-automatic with fencing (D6): one on-call confirmation, because two writers can charge a payment twice.
- us-east-2 stays data and backups only; plan B of D7 is unchanged.
- Environments opt in with `standby_enabled` in `env.hcl` (stage); dev has no standby.

## Consequences

- Reads in us-east-1 can lag by the replication lag (alert at 5 s). The application must tolerate stale reads or pin read-after-write requests to Frankfurt.
- Standby compute and readers add cost in stage and prod; Infracost must estimate it before the first apply.
- The switch runbook shrinks to promotion and traffic shift; the compute creation steps and the 60 minute RTO budget of D7 need a new calculation.
- The write proxy from us-east-1 to Frankfurt is a deploy-side task, tracked in the handoff to the k8s-engineer.
