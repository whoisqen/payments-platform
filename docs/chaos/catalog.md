# Chaos experiment catalog

Failure mode ids follow the `<layer>-<component>-<failure>` form of section 25.1; the catalog of failure modes does not exist in the repository yet, so the ids and alert names below are proposals that `tools/coverage/alerts` must match once it does.
Every experiment runs in stage under background load (`tests/load/scenarios/daily-peak.js`), with the stop condition "burn rate 14.4 or authorization rate drop above 2 pp" (the `chaos-stop` alarm), and never during a freeze or an open incident.

| Experiment | File | Failure mode id | Expected alert | Hypothesis |
|---|---|---|---|---|
| AZ loss | `tests/chaos/fis/az-loss.json` | `compute-az-loss` | `AzUnreachable` | SLOs hold on two AZs, RTO 1 min |
| Node loss | `tests/chaos/fis/node-loss.json` | `compute-node-notready` | `EksNodeNotReady` | PDB and anti-affinity hold, Karpenter replaces the node |
| Spot interruption of workers in one AZ | `tests/chaos/fis/workers-spot-interruption.json` | `compute-spot-interruption` | `SpotInterruptionBurst` | drainer and consumer move, drain lag stays below 30 s |
| MemoryDB failover | `tests/chaos/fis/memorydb-failover.json` | `data-memorydb-failover` | `MemoryDbFailover` | no lost writes, 5xx below 0.1% for at most 30 s |
| Aurora writer failover | `tests/chaos/fis/aurora-writer-failover.json` | `data-aurora-writer-failover` | `AuroraWriterFailover` | hot path unaffected, stream length back below 5,000 in 2 min |
| Kafka broker loss | `tests/chaos/fis/msk-broker-loss.json` | `messaging-msk-broker-down` | `MskUnderReplicatedPartitions` | payment path unaffected, consumer lag recovers in 10 min |
| PSP timeout injection | `tests/chaos/chaos-mesh/psp-timeout.yaml` | `app-psp-timeout` | `PspTimeoutRateHigh` | unknown state and sync, no double charge, bulkhead holds |
| Drainer stall | `tests/chaos/chaos-mesh/drainer-stall.yaml` | `app-drainer-stall` | `RedisStreamLengthHigh` | stream grows, no duplicates, drain lag below 5 s after recovery |
| DNS failure | `tests/chaos/chaos-mesh/dns-failure.yaml` | `edge-dns-resolution-failure` | `DnsResolutionErrorsHigh` | pooled connections keep serving, no retry of a charge |
| Region switch to us-east-1 (D7) | `tests/chaos/region-switch/scenario.json` | `dr-region-switch` | `AuroraGlobalReplicationLagHigh` (lag over 5 s), `DrTestOverdue` | RTO 60 min, RPO 10 s plus drain lag p99 5 s, one writer, warm ratio 75% (D8) |
| Region switch plan B to us-east-2 | `tests/chaos/region-switch/plan-b.json` | `dr-region-switch-plan-b` | same as above | RTO 75 min after 10 min without capacity in us-east-1 |

Region-switch runs are quarterly, once per recovery region in turn; the other experiments are weekly in stage and a monthly fire-drill (section 25.4) checks that the alert reaches the PagerDuty test service within `detect_within`.
Results go to `docs/chaos/results.md` after each run.
