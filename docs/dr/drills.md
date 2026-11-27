# Disaster recovery drills

Recovery that is not practised does not work when it is needed. Only prod has a standby region, so the full region switch is exercised in prod. It runs as a planned, announced game day with on-call approval, followed by the switch back. Stage has no standby region and exercises only the component steps: fencing, and promotion of a test cluster.

| Drill | How often | How | Proof |
|---|---|---|---|
| Restore test of Aurora and DynamoDB | daily | AWS Backup restore testing, then an SSM Automation validator | `RestoreSuccess`, `RestoreDurationSeconds`; alerts `RestoreTestFailed`, `RestoreDurationNearTarget`, `RestoreTooSlow`, `RestoreTestStale` |
| AZ loss, node loss, Spot interruption, MemoryDB and Aurora writer failover | per the chaos catalog | AWS FIS templates in `tests/chaos/fis/` | the alert named in `docs/chaos/catalog.md` fires and SLOs hold |
| Component steps of the region switch in stage: fencing, promotion of a test cluster | with the quarterly game day | the SSM documents of the switch | each step within its budget |
| Prod game day: region switch to the us-east-1 hot standby, then back | quarterly | step DAG `tests/chaos/region-switch/scenario.json`, run by SSM Automation through `/incident` with on-call approval; runbook `docs/runbooks/meta/promote-standby-region.md` | measured RTO at most 60 min; `dr_switch_test_last_success_timestamp_seconds`; `DrSwitchTestOverdue` fires after 100 days |

## Timed region switch

Each step has a budget in minutes, and the runner adds them along the dependency graph:

| Step | Budget (min) | Starts after | Ends at (min) |
|---|---:|---|---:|
| `detect-confirm` | 10 | start | 10 |
| `fence-frankfurt` | 2 | `detect-confirm` | 12 |
| `promote-aurora` (point of no return) | 3 | `fence-frankfurt` | 15 |
| `warm-cache` (priority keys from Aurora, D8) | 15 | `promote-aurora` | 30 |
| `traffic-switch` | 2 | `warm-cache` | 32 |
| `verify-reconciliation` (after the RTO) | 5 | `traffic-switch` | 37 |

- The critical path is 32 minutes against the 60-minute target. The standby already runs at the working size, so no step builds or scales compute.
- The drill passes only if every steady-state hypothesis holds:
  - authorization rate within 2 pp of the baseline;
  - overhead p99 under 150 ms;
  - 5xx within the SLO;
  - exactly one writer;
  - 75% of priority keys warm before a cell takes traffic;
  - drain lag p99 under 5 s;
  - no unrefunded duplicate charge.
- `promote-aurora` is the only point of no return. Before it, a tripped abort condition stops the run and removes the fence. After it, the run halts and escalates to on-call.
- The game day ends with the planned failback of [failover.md](failover.md). us-east-1 then returns to being the hot standby.
- `python3 runner.py scenario.json --dry-run` in `tests/chaos/region-switch/` validates the graph and prints this timeline.
- Record the real duration of every step next to its budget. A step over its budget is a finding even when the total stays under 60 minutes. A critical path above 32 minutes in two game days in a row is a review condition of ADR-0019.

The switch dashboard (`observability/dashboards/l3-data/dr-switch.json`) shows each run. The measured RTO, RPO, step durations and evidence go to the issue of the drill.
