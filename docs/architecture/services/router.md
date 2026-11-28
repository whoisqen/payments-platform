# router

The public payments API of one cell: the Hyperswitch router built from `vendor/hyperswitch`. Owner team: `payments-core`. CDE: yes.

## What it does and why it exists

The router is where a payment lives while it is being processed. It:

- authenticates the merchant's API key against its own cell's database;
- creates and changes payments, refunds and disputes, with an [idempotency key](../domain/payment-lifecycle.md#idempotency-keys) on every write;
- hands card details to the [locker](locker.md) and keeps only the token;
- picks a PSP ([routing](../domain/platform-concepts.md#routing)) and calls it through the egress path;
- receives incoming PSP webhooks and sends the first delivery of outgoing merchant webhooks;
- enqueues delayed work for the [scheduler](scheduler.md): PSP sync after a timeout, webhook retries.

It keeps payment state in MemoryDB and never writes PostgreSQL on the hot path ([write-behind](data-stores.md#memorydb)); the [drainer](drainer.md) moves the state to Aurora. This keeps the answer to the merchant fast and independent of database latency.

One router deployment runs in every cell (`cell-0` to `cell-3`, `spare`), each in its own EKS cluster, namespace `payments`.

## Requests it takes and calls it makes

| Direction | Peer | Port and protocol | Purpose |
|---|---|---|---|
| in | [payments-edge](payments-edge.md) through the router gateway of the cell (internal NLB, port 8443, mutual TLS that admits only the `edge-client` certificate), principal `cluster.local/ns/payments/sa/router-istio` | 8080 HTTP inside Istio mTLS | merchant API calls and PSP webhooks |
| in | PostSync smoke Job, principal `cluster.local/ns/payments/sa/smoke` | 8080 | live smoke test after each deployment |
| in | Prometheus (`monitoring` namespace) | 8080 `/metrics` | scraping |
| out | MemoryDB of the cell | 6379 TLS, ACL user `<cell>-router` | state, drainer stream |
| out | Cell Aurora through RDS Proxy | 5432 TLS `verify-full`, login `hs_app` | reads, configuration writes |
| out | [locker](locker.md) in the locker cluster, `locker.payments.svc.locker.<cluster_domain>`: internal NLB, locker gateway | 3001, mutual TLS with the `router-client` certificate (`lockerClient`), JWE payload inside | store and fetch cards |
| out | PSPs | 443 HTTPS through the Istio egress path, Network Firewall and NAT | authorize, capture, refund, sync |
| out | merchant webhook endpoints | 443 HTTPS through the egress path | first delivery of outgoing webhooks |
| out | AWS KMS | 443 | data-key encryption (`aws_kms`) |
| out | OpenTelemetry collector | 4317 gRPC | traces and metrics |

The NetworkPolicy opens the data ports 5432 and 6379 only to the cell's data subnets (`global.dataCidrs`), the locker NLB subnets (`global.lockerCidrs`) on 3001, the mesh exits in `istio-system` on 443 and 15012, DNS, and the collector on 4317.

Main API paths: `POST /payments`, `POST /payments/{payment_id}/confirm`, `POST /payments/{payment_id}/capture`, `POST /payments/{payment_id}/cancel`, `GET /payments/{payment_id}`, `POST /refunds`, incoming PSP webhooks at `/webhooks/{merchant_id}/{connector_id_or_name}`. Health: `/health` (liveness), `/health/ready` (deep check of MemoryDB and PostgreSQL).

## Data it reads and writes

| Store | Reads | Writes |
|---|---|---|
| [MemoryDB](data-stores.md#memorydb) | payment state, idempotency answers, caches | payment state; entries in `{shard_N}_drainer_stream` |
| [Cell Aurora](data-stores.md#cell-aurora) | payments, merchant accounts, API keys, connector accounts | merchants, profiles, keys, connector accounts; `process_tracker` tasks for sync and webhook retries |
| [Locker](locker.md) | cards by token for the one PSP call that needs them | new cards, returns a token |
| [DynamoDB cell map](data-stores.md#dynamodb-cell-map) | read access granted by IAM | never |

Events: `ROUTER__EVENTS__SOURCE` is `logs` while `global.hyperswitch.events.kafka` is `false` (the default in `platform-common`); with `kafka: true` the router writes to the topics `<topicPrefix>-<name>-events` on MSK. See [analytics consumers](analytics-consumers.md).

## Configuration and secrets

Non-secret settings are environment variables built by `platform-common` (`templates/hyperswitch/_env.tpl`) from `global.hyperswitch` in the `payments-cell` umbrella and the layers in `deploy/envs/<env>/<region>/<cell>/values.yaml`:

- config file `/app/config/deployments/production.toml` baked into the image;
- database host (RDS Proxy endpoint), database `hyperswitch`, user `hs_app`, pool 10 (replica pool 5);
- MemoryDB cluster endpoint, port 6379, cluster mode, TLS, user `<cell>-router`;
- KMS key `alias/pay-<env>-<region-short>-<cell>`;
- tenant `public`, base URL and control center URL of the environment;
- locker host `locker.payments.svc.locker.<clusterDomain>:3001`, built from `global.hyperswitch.locker.clusterDomain` (the in-cluster Service only when neither it nor `locker.host` is set);
- CORS origin: the panel of the environment, never a wildcard.

A values file cannot carry a secret: `platform-common.noPlainSecrets` fails the render for any variable ending in `PASSWORD`, `SECRET`, `PRIVATE_KEY`, `ENC_KEY`, `HASH_KEY`, `API_KEY`, `ENCRYPTION_KEY` or `_DSN`.

Secrets come from Vault through ExternalSecret `router-vault` (ClusterSecretStore `vault`, refresh 1 h, read at pod start):

| Variable | Vault path (`secret/<env>/<cell>/...`) | Field |
|---|---|---|
| `ROUTER__MASTER_DATABASE__PASSWORD`, `ROUTER__REPLICA_DATABASE__PASSWORD`, `ROUTER__ANALYTICS__SQLX__PASSWORD` | `router/database` | `password` |
| `ROUTER__REDIS__PRIMARY_PASSWORD` | `router/redis` | `password` |
| `ROUTER__SECRETS__MASTER_ENC_KEY` | `shared/app` | `master_enc_key` |
| `ROUTER__SECRETS__ADMIN_API_KEY` | `shared/app` | `admin_api_key` |
| `ROUTER__SECRETS__JWT_SECRET` | `shared/app` | `jwt_secret` |
| `ROUTER__API_KEYS__HASH_KEY` | `shared/app` | `api_keys_hash_key` |
| `ROUTER__USER_AUTH_METHODS__ENCRYPTION_KEY` | `shared/app` | `user_auth_encryption_key` |
| `ROUTER__JWEKEY__VAULT_ENCRYPTION_KEY`, `..._VAULT_PRIVATE_KEY`, `..._TUNNEL_PRIVATE_KEY` | `shared/locker` | `vault_encryption_key`, `vault_private_key`, `tunnel_private_key` |

The Sentry DSN comes from Secrets Manager `<prefix>/<env>/sentry/router-dsn` when `container.sentryDsn.remoteKey` is set. A rotation is: write the new value, wait for the refresh, restart the rollout.

## Scaling and resources

- HPA from 20 to 90 pods on CPU 70%. The chart notes a planning figure of 10 requests per second per pod until the breakpoint test confirms more.
- Each pod requests 1 vCPU and 3 GiB, memory limit 3 GiB, no CPU limit (no throttling during a PSP call). Two actix workers per pod.
- Runs on the On-Demand `payments` node pool with no Spot toleration: a pod killed mid-call to a PSP would leave the payment in the [unknown state](../domain/payment-lifecycle.md#why-a-charge-is-never-retried).
- PDB `maxUnavailable: 10%`. Shutdown: 15 s pre-stop, 30 s server shutdown timeout, 60 s grace period, so in-flight PSP calls finish.
- Readiness waits for the cache warm-up: at least 75% warm (`warmup.minRatio: 0.75`), at most 300 s.
- Rollout: Argo Rollouts canary 1% -> 5% -> 25% -> 50% -> 100%, 10 minutes of analysis per step. The analysis stops the rollout when the error rate exceeds 0.05%, p99 latency grows by more than 150 ms, or the authorization rate drops. Sync wave 1, after the drainer.

## Failure modes and what the user sees

| Failure | Effect | Merchant sees |
|---|---|---|
| PSP timeout on authorize | no retry (`psp-authorize` `max_attempts: 0`); payment enters the unknown state; a sync task is queued | `processing`; a webhook later with the final status |
| PSP technical errors above threshold | circuit breaker opens, traffic goes to the fallback PSP | payments succeed through the other PSP |
| Locker slow or down | `router-locker` retried at most twice within 300 ms | `5xx` on confirm with a new card; saved-card payments that need the card also fail |
| MemoryDB full | `noeviction` rejects writes | `5xx` on writes; reads continue |
| Aurora unavailable | reads of data not in MemoryDB fail; readiness fails | `5xx` on those reads; pods leave the load balancer |
| Pod lost | Istio sends new requests to the others | an in-flight confirm may end in the unknown state, settled by sync |
| Bad release | canary analysis aborts | at most the canary share of one cell's traffic is affected |

## Metrics and alerts

Metrics from `/metrics` and the OpenTelemetry pipeline: `http_server_requests_total` (by route and code), `psp_requests_total`, `psp_request_duration_seconds`, `payment_attempts_total`, `circuit_breaker_state`, `cache_warm_ratio`, `retry_total`, `retry_budget_exhausted_total`.

| Alert | Severity | Runbook |
|---|---|---|
| `PaymentsAuthorizationAvailabilityBurn*`, `PaymentsPlatformOverheadLatencyBurn*`, `PaymentsStatusReadBurn*` | critical (fast), warning (slow) | [SLO runbooks](../../runbooks/slo/authorization-availability.md) |
| `PSPDegraded` | critical | [psp-degraded](../../runbooks/application/psp-degraded.md) |
| `SyntheticPaymentFailing` | critical | [synthetic-payment-failing](../../runbooks/application/synthetic-payment-failing.md) |
| `RetryBudgetExhausted` (`psp-sync`, `router-locker`) | critical | [retry-budget-exhausted](../../runbooks/application/retry-budget-exhausted.md) |
| `Router5xxRateHigh` | warning | [router5xx-rate-high](../../runbooks/application/warnings.md#router5xx-rate-high) |
| `PspLatencyP99High`, `PspCircuitBreakerOpen`, `AuthorizationRateDrop` | warning | [application warnings](../../runbooks/application/warnings.md#psp-circuit-breaker-open) |
| `OrphanPaymentWebhooks` | warning | [orphan-payment-webhooks](../../runbooks/application/warnings.md#orphan-payment-webhooks) |
| `CacheWarmRatioLow` | warning | [cache-warm-ratio-low](../../runbooks/data/warnings.md#cache-warm-ratio-low) |
| `HpaAtMaxReplicas`, `PodOOMKilled` | warning | [compute warnings](../../runbooks/compute/warnings.md#hpa-at-max-replicas) |

Rules: `observability/alerts/application/`, SLOs in `observability/slo/`.

## Where in the repo

| Path | What |
|---|---|
| `vendor/hyperswitch/crates/router` | Upstream router code |
| `docker/router/Dockerfile` | Image |
| `deploy/charts/router/` | Chart (Rollout, HPA, NetworkPolicy, AuthorizationPolicy, canary analysis) |
| `deploy/charts/payments-cell/` | Umbrella that installs router, drainer, scheduler and migrations per cell |
| `deploy/charts/platform-common/templates/hyperswitch/` | Shared Hyperswitch environment, Vault mapping |
| `deploy/envs/<env>/<region>/<cell>/values.yaml` | Endpoints per cell |
| `policy/resilience/policy.yaml` | Timeouts and retries per dependency |
| `observability/alerts/application/`, `observability/slo/` | Alerts and SLOs |
