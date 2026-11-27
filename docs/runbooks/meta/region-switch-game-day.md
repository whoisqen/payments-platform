# RegionSwitchGameDay

Layer backup-dr (a procedure that no alert points to; `DrSwitchTestOverdue` reminds of it), service aurora, owner data-platform-oncall.

## Symptom

The quarterly prod game day is due, or `DrSwitchTestOverdue` fired. us-east-1 is the prod hot standby at full size ([ADR-0019](../../adr/0019-hot-standby-recovery-region.md)), so the game day proves that the switch moves the whole load to it within the 60-minute RTO and that the switch back works. Only prod has a standby region; stage exercises the component steps.

## Diagnostics

1. Announce the game day to merchants and the PSP contacts, and freeze changes for its duration.
2. Check the preconditions of `tests/chaos/region-switch/scenario.json`: Aurora Global lag at most 5 s, and exactly one writer per global cluster.
3. Run `python3 runner.py scenario.json --dry-run` in `tests/chaos/region-switch/`. It must print a critical path of 32 min against a target of 60.
4. Check that the us-east-1 cells are healthy and serve synthetic traffic: Argo CD shows every us-east-1 Application Synced and Healthy, and the `use1` probe point is green.

## Actions

Every action runs through the SSM Automation run of the scenario, which is audited. Record the start and end time of each step.

1. `detect-confirm` (10 min): open the game-day incident and confirm the simulated outage of Frankfurt.
2. `fence-frankfurt` (2 min): the drop rule goes into `psp-fence`. Abort condition A1: no writes in Frankfurt before promotion.
3. `promote-aurora` (3 min), the point of no return: `scripts/dr/failover.py` promotes the us-east-1 instance of every global cluster. Abort condition A2: lag above 10 s.
4. `warm-cache` (15 min): each cell waits for 75% of its priority keys to be warm (D8).
5. `traffic-switch` (2 min): Route 53 and Global Accelerator move the traffic to us-east-1. Abort condition A3: test merchants losing more than 2 pp of authorization rate.
6. `verify-reconciliation` (5 min, after the RTO): run PSP reconciliation over the `reconcile-window`. No duplicate charge may remain unrefunded.
7. Switch back with `scripts/dr/failover.py --mode failback` per cell after a named approver confirms ([failback](../../dr/failover.md#failback-planned)).

## Escalation

If a step exceeds its budget, or the run halts after promotion, page the incident commander. A measured RTO above 60 min opens the review of ADR-0019. Default chain: the primary acknowledges within 5 min, the secondary is paged at 5 min and the incident commander at 15 min (section 20.6).

## Evidence

The measured RTO and RPO, the duration of every step next to its budget, the abort conditions checked, and a link to `observability/dashboards/l3-data/dr-switch.json`. Attach them to the issue of the game day.
