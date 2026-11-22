# region-switch

Quarterly test of a full cell switch (D7): `scenario.json` to us-east-1 (RTO 60 min, critical path 54), `plan-b.json` to us-east-2 after 10 min without capacity (RTO 75, path 64).
Each file holds preconditions, steady-state hypotheses S1-S7, abort conditions and the step DAG; `promote-aurora` is the only point of no return.
Before it a tripped condition aborts and un-fences Frankfurt; after it the run halts and escalates to on-call.
`python3 runner.py scenario.json --dry-run` validates the DAG and prints the timeline; real execution is an SSM Automation run, not this script.
The steps run against the stage account; a prod switch goes through `/incident` with on-call approval.
