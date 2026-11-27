# Chaos and load testing

## What it is

Load tests with k6 and chaos experiments with AWS FIS and Chaos Mesh, all in stage, which has the prod size and topology. Smoke, end-to-end and contract tests run offline in CI.

## Why

Capacity numbers and failure behaviour are claims until a test shows them. Running experiments on purpose, with a stop condition, is cheaper than learning the same lessons in an incident.

## How it works

### Load model

The design targets come from `manifests/constraints.yaml`: 160 payments per second on average, 480 at the daily peak, 1,430 at a sale peak and 2,860 for stress. One payment is about seven API calls (create, confirm, two status reads, payment methods or SDK session, the PSP webhook, capture or refund), so the sale peak is about 10,000 requests per second.

| Scenario | Shape |
|---|---|
| `smoke` | a few payments, end to end |
| `average`, `daily-peak`, `sale-peak`, `stress` | 160, 480, 1,430, 2,860 payments per second, open model (`ramping-arrival-rate`) |
| `spike`, `soak` (8 h), `breakpoint` | sudden jump, long run, rise until a threshold breaks |
| `shedding` | proves the class order of load shedding |

Thresholds come from the SLOs. The target is the dummy PSP connector with test merchants, never real money. A mock PSP with configurable latency, errors and timeouts lives in `tests/load/mock-psp/`.

In stage the k6 Operator runs the scenarios as CronJobs: daily peak every night, stress weekly, soak weekly, spike monthly; the others on demand. The chart refuses to render for any environment other than stage, and every scenario refuses at start unless the target is stage, no freeze is on and no incident is open.

### Chaos experiments

| Experiment | Tool | Hypothesis |
|---|---|---|
| AZ loss | FIS | SLOs hold on two AZs |
| Node loss, Spot interruption | FIS | PDBs hold, Karpenter replaces nodes, drain lag stays low |
| MemoryDB failover, Aurora writer failover | FIS | no lost writes, short and small error burst |
| MSK broker loss | FIS (SSM document) | payment path unaffected |
| PSP latency | FIS pod network latency | unknown state and sync, no double charge |
| PSP timeout, drainer stall, DNS failure | Chaos Mesh | as above, no duplicates, pooled connections keep serving |
| Hot merchant | k6 | the hot tenant gets 429 with `Retry-After`, the others keep their SLOs |
| Region switch (prod game day) | step DAG run by SSM Automation | see [DR drills](../../dr/drills.md) |

Every experiment has a written hypothesis and a stop condition. The composite `chaos-stop` alarm combines an SLO burn rate of 14.4, an authorization rate drop over 2 points, edge health and an Aurora writer check; missing data counts as breaching and blocks the run. Blast radius is at most one AZ or one cell, and a guard (`tests/chaos/lib/guard.py`) refuses prod, a freeze or an open incident. The catalog in `docs/chaos/catalog.md` links each experiment to the alert it must raise.

### Offline suites

| Suite | Proves |
|---|---|
| `tests/smoke` | a synthetic payment (create, capture, read, refund) through a fake edge for every routed cell; probes and ports of every chart |
| `tests/e2e` | promotion dev to stage by image digest |
| `tests/contracts` | environment values against chart schemas; every alert has a failure mode and a runbook |

Run all three with `python3 -m unittest discover -s tests`. After every sync in dev and stage the PostSync smoke Job repeats the synthetic payment against the live cell.

## Where in the repo

| Path | What |
|---|---|
| `tests/load/` | k6 scenarios, profiles, mock PSP |
| `tests/chaos/` | FIS templates, Chaos Mesh manifests, region switch, guard |
| `infra/modules/fis-prereqs`, `fis-experiments` | Stop alarm, boundary, FIS templates |
| `deploy/platform/k6`, `deploy/platform/smoke` | k6 Operator and runs; PostSync smoke |
| `docs/chaos/` | Experiment catalog |
