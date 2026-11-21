---
name: retry-timeout
description: Define timeouts, retries, backoff and budgets for a dependency.
---

# retry-timeout

- Delay = random(0, min(cap, base x 2^n)) (full jitter); values per dependency come from `policy/resilience/policy.yaml`; never edit `policy/resilience/generated/` by hand.
- Retry only idempotent operations; never retry a charge; retry budget 10% of normal traffic; propagate the request deadline; retry only at the layer closest to the dependency.
- Do not retry 4xx except 408 and 429 (honour `Retry-After`); fail fast when the circuit breaker is open.
- Prove it with the retry-storm chaos scenario: load on a failing dependency grows at most 1.1x.
