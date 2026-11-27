# region-switch

Quarterly game day of a full switch (D7) to the prod hot standby in us-east-1: `scenario.json`. Only prod has a standby region, so the switch is a planned, announced prod exercise with on-call approval, followed by the switch back.
Each file holds preconditions, steady-state hypotheses S1-S7, abort conditions and the step DAG; `promote-aurora` is the only point of no return.
Before it a tripped condition aborts and un-fences Frankfurt; after it the run halts and escalates to on-call.
`python3 runner.py scenario.json --dry-run` validates the DAG and prints the timeline; real execution is an SSM Automation run, not this script.
The real run is an SSM Automation run through `/incident` with on-call approval; stage exercises only the component steps (fencing, promotion of a test cluster).
