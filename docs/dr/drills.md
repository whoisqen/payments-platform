# Disaster recovery drills

Recovery that is not practised does not work when it is needed. Drills run in stage, which has the prod topology and the same warm standby.

| Drill | How often | How | Proof |
|---|---|---|---|
| Restore test of Aurora and DynamoDB | daily | AWS Backup restore testing, then an SSM Automation validator | `RestoreSuccess`, `RestoreDurationSeconds`; alerts `RestoreTestFailed`, `RestoreDurationNearTarget`, `RestoreTooSlow`, `RestoreTestStale` |
| AZ loss, node loss, Spot interruption, MemoryDB and Aurora writer failover | per the chaos catalog | AWS FIS templates in `tests/chaos/fis/` | the alert named in `docs/chaos/catalog.md` fires and SLOs hold |
| Region switch to us-east-1 | quarterly | step DAG `tests/chaos/region-switch/scenario.json`, run by SSM Automation | `dr_switch_test_last_success_timestamp_seconds`; `DrSwitchTestOverdue` fires after 100 days |
| Region switch plan B to us-east-2 | quarterly | `tests/chaos/region-switch/plan-b.json` | as above |

## Region switch drill

- Each scenario file holds preconditions, steady-state hypotheses, abort conditions and the step DAG: confirm the outage, fence Frankfurt, promote Aurora, bring up compute, sync the cells and warm caches, move traffic, reconcile with the PSPs.
- In an environment with the warm standby the compute steps find the clusters already running, so the critical path is detection, fencing, promotion and the traffic shift.
- `promote-aurora` is the only point of no return. Before it, a tripped abort condition stops the run and removes the fence; after it, the run halts and escalates to on-call.
- A cell takes traffic once 75% of its priority hot keys are warm; after 5 minutes it takes traffic anyway with a non-paging alert.
- `python3 runner.py scenario.json --dry-run` in `tests/chaos/region-switch/` validates the DAG and prints the timeline.
- The steps run against the stage account; a prod switch goes through the incident process with on-call approval.

The switch dashboard (`observability/dashboards/l3-data/dr-switch.json`) shows each run; the measured RTO and RPO and the evidence go to the issue of the drill.
