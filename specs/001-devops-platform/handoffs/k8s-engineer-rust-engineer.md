# k8s-engineer to rust-engineer

Requests from the Helm charts under `deploy/charts/`; none is implemented in the charts alone.

- D8 warm-up gate: `router` receives `CACHE_WARM_MIN_RATIO=0.75` and `CACHE_WARM_MAX_WAIT_SECONDS=300`; `GET /health/ready` must return 200 once `cache_warm_ratio` reaches the ratio or the wait ends, whichever comes first, because a readiness probe alone cannot express "ready anyway after 5 minutes".
- Scheduler probes: the chart probes `GET /health` on port 3000 and sets `ROUTER__SCHEDULER__SERVER__HOST=0.0.0.0`; confirm the variable name, the default is `127.0.0.1`, which the kubelet cannot reach.
- Drainer KEDA trigger names the stream `{shard_0}_drainer_stream` and the group `drainer_group`; confirm the real names and the shard count.
- Canary analysis reads `payments_authorization_rate{service=...}`; the metric name is a contract with `observability/`.
