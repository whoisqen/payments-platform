# tests/chaos

Chaos experiments as code, stage only; each has a hypothesis and a stop condition, none runs during a freeze or an open incident.

- `fis/`: AWS FIS templates (AZ loss, node loss, spot interruption, MemoryDB failover, Aurora writer failover, MSK broker loss).
- `chaos-mesh/`: PSP timeout, drainer stall, DNS failure.
- `region-switch/`: quarterly full-switch scenario of D7 (us-east-1, then us-east-2) and the plan-B variant, with a dry-run runner.
- `lib/`: guard (freeze, incident, environment) and the FIS template validator.
- Offline proof: `python3 -m unittest discover -s tests` from this directory. Catalog: `docs/chaos/catalog.md`.
- Templates and manifests carry `${STAGE_ACCOUNT_ID}`, `${NAME_PREFIX}`, `${REGION}` and `${REGION_SHORT}`; fill them with `envsubst` from `config/platform.yaml` before `aws fis create-experiment-template` or `kubectl apply`.
- `hot-merchant.js`: k6 chaos scenario for per-merchant rate limiting (below).
- Guard for k6: `python3 lib/guard.py stage` (exit 1 refuses prod, a freeze or an open incident); the scenarios also refuse at init unless `TARGET_ENV=stage`, `FREEZE` is not `true`, `OPEN_INCIDENTS` is 0 and `BASE_URL` is not a prod or CDE host (`../load/lib/stage-guard.js`).

## hot-merchant.js and shedding.js

- Hypothesis: one tenant rising from 5% to 60% of traffic in 60 s is limited at the edge (429 with `Retry-After`, never 5xx) and the other merchants keep success rate, overhead p99 below 150 ms and status p99 below 50 ms; their payments are not shed. Load shedding past 2,000 RPS per gateway pod drops lists and reports first, reads next, payments last, with 5xx below 0.1%.
- Stop condition: the `chaos-stop` alarm (burn rate 14.4 or authorization rate drop above 2 pp), or any k6 threshold with `abortOnFail`; stage only.
- Run (stage test merchants on the dummy PSP connector, never real money):
  `python3 lib/guard.py stage && k6 run -e TARGET_ENV=stage -e BASE_URL=... -e MERCHANT_API_KEY=... -e TEST_PAYMENT_TOKEN=... -e HOT_MERCHANT_ID=... -e OTHER_MERCHANT_IDS=a,b,c -e TOTAL_RPS=1000 hot-merchant.js`
  and `k6 run -e TARGET_ENV=stage -e BASE_URL=... -e MERCHANT_API_KEY=... -e TEST_PAYMENT_TOKEN=... -e MERCHANT_ID=... -e PODS=1 ../load/scenarios/shedding.js`.
- Expected: every threshold passes. `TOTAL_RPS` must put 60% of it above the stage limit of the hot tenant, otherwise `shed_rate{merchant_role:hot,phase:hot}` stays 0 and the run fails. `retry_after_present` has no samples when no 429 occurs, which also fails the run.
- Fail-open proof (manual, stage only, not automated): scale the rate limit service to zero (`kubectl -n <ratelimit-namespace> scale deploy/<ratelimit> --replicas=0`, by an operator with stage access), then run `hot-merchant.js` at the baseline rate. Fail-open holds when there are no 5xx, `ok_rate` of every merchant stays above 99.9%, the hot tenant is no longer limited per merchant (its `shed_rate` falls to the local pod limit only) and the `RateLimitHitsMerchant` counter stays flat; restore the replicas afterwards. Needs `failure_mode_deny: false` on the edge filter.
- Assumptions: paths and headers live in `../load/lib/edge.js` (`x-merchant-id`; class by path: payments, read, list); the payments-edge chart carries only the local 2,000 RPS token bucket today, so the per-merchant limit, class-based shedding and `Retry-After` must exist in stage before these scenarios can pass.
