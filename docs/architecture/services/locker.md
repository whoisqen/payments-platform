# locker

The card vault: the Hyperswitch card vault (`juspay/hyperswitch-card-vault`) built from `vendor/card-vault` with the `release` features. It is the only component that stores a PAN. Owner team: `payments-core`. CDE: yes.

## What it does and why it exists

The locker swaps card details for a [token](../domain/cards-and-compliance.md#tokenization-and-the-locker) and back. Everything else in the platform (payment records, streams, PostgreSQL, analytics, webhooks) carries only the token. Keeping the PAN in one small service with its own database and its own key keeps the part of the platform that can leak a card as small as possible.

One locker serves all cells of a region, because a card belongs to the customer and the same customer may pay merchants in different cells. It runs in its own cluster `pay-<env>-<region-short>-locker`, namespace `payments` (`deploy/argocd/templates/applicationset-shared.yaml`). Only the cell node groups reach its NLB, and only the NLB reaches the locker pods.

## Requests it takes and calls it makes

| Direction | Peer | Port and protocol | Purpose |
|---|---|---|---|
| in | [router](router.md) of every cell, from its own cluster through the internal NLB of `infra/modules/locker-endpoint` (host `locker.payments.svc.locker.<cluster_domain>`) and the locker gateway (`deploy/charts/payments-locker`, port 3001) | 3001, mutual TLS: the gateway holds a `locker-gateway` certificate of the Vault mesh PKI and admits only the `router-client` certificate with URI SAN `spiffe://payments-platform/ns/payments/sa/router`; then HTTP inside Istio mTLS (PeerAuthentication STRICT) | card API |
| in | Prometheus (`monitoring` namespace) | 9091 HTTP `/metrics` | scraping, on a separate listener |
| out | Locker Aurora through RDS Proxy | 5432 TLS `verify-full`, login `locker_app` | card records |
| out | AWS KMS and STS interface endpoints (`global.endpointCidrs`) | 443 | decrypt the master keys at start |
| out | EKS Pod Identity agent `169.254.170.23` | 80 | AWS credentials |

Card API (`vendor/card-vault/src/app.rs`), all `POST` unless stated:

| Path | Purpose |
|---|---|
| `/data/add` (also `/cards/add`) | store a card, return a token |
| `/data/retrieve` | return the card for a token |
| `/data/delete` | delete a card; rate limited by `config.limit` (1 request per 60 s) |
| `/data/fingerprint` | stable fingerprint of a card, for duplicate checks |
| `/api/v2/vault/{add,retrieve,delete,fingerprint}` | v2 API |
| `/health` | probes |
| `/custodian/*` | key custodian endpoints of the `key_custodian` feature |

The payload between router and locker is also protected by JWE/JWS: the router holds `vault_encryption_key` and `vault_private_key` (Vault `shared/locker`), the locker holds `locker-private-key` and each tenant's public key.

## Data it reads and writes

| Store | Reads and writes |
|---|---|
| [Locker Aurora](data-stores.md#locker-aurora), database `locker` | tables `merchant`, `locker`, `hash_table`, `fingerprint`, `vault`, `entity`, `reverse_lookup` |

Each card is encrypted with the tenant's master key before it is written. The master key is stored as KMS ciphertext and decrypted once at start under the locker role; only that role may use `alias/pay-<env>-<region-short>-locker`. An in-process cache keeps merchant keys, hash-table, fingerprint and entity records for at most 2 hours idle (`cache.tti: 7200`, at most 5,000 entries). The locker uses no Redis.

The CVV is never stored, not even here.

## Configuration and secrets

Non-secret settings are the `config` section of `deploy/charts/locker/values.yaml`, rendered as `LOCKER__<SECTION>__<KEY>` variables; the schema rejects secret keys there. Per region, `deploy/envs/<env>/<region>/locker/values.yaml` sets the RDS Proxy host, the KMS alias and the pod security group.

| Setting | Value |
|---|---|
| Database | `locker` on the RDS Proxy endpoint, user `locker_app`, pool 10, min idle 2 |
| KMS | `secrets_management.secrets_manager: aws_kms`, key `alias/pay-<env>-<region-short>-locker` |
| External key manager | `disabled` |
| Tenants | `public` (schema `public`) |
| Metrics | Prometheus listener on 9091, background collection every 15 s |

Secrets through ExternalSecret `locker-secrets` from store `vault` (refresh 1 h, read at start):

| Vault path (`secret/<env>/locker/...`) | Field | Variable |
|---|---|---|
| `database` | `password` | `LOCKER__DATABASE__PASSWORD` |
| `jwe` | `locker-private-key` | `LOCKER__SECRETS__LOCKER_PRIVATE_KEY` |
| `tenants/<id>` | `master-key`, `public-key` | `LOCKER__TENANT_SECRETS__<ID>__*` |

Vault policy `locker-<env>-read` reads `secret/data/<env>/locker/*`. The `locker_app` password is the same value as the RDS Proxy secret and both rotate together.

## Scaling and resources

- HPA from 5 to 24 pods on CPU 70%. The chart's planning figure is 300 requests per second per pod.
- 1 vCPU and 1 GiB per pod, memory limit 1 GiB.
- On-Demand `payments` node pool, no Spot toleration.
- PDB `maxUnavailable: 10%`, grace period 60 s.
- The pod ENI gets the `locker_pod` security group (`SecurityGroupPolicy`); it is the only group the locker Aurora proxy admits.
- Rollout: Argo Rollouts canary by Istio weight, 1% -> 10% -> 50% -> 100% of router traffic, 10 minutes of analysis per step, stopped at an error rate above 0.05% or a p99 increase above 150 ms.

## Failure modes and what the user sees

| Failure | Effect | User sees |
|---|---|---|
| Locker slow | the router waits at most 300 ms and retries at most twice (`router-locker`) | slower confirms; then `5xx` |
| Locker down | no new cards can be stored or read | payments with a new or saved card fail; payments that need no card data (status reads, refunds) keep working |
| KMS unavailable at start | the master keys cannot be decrypted; the pod does not become ready | running pods keep serving; new pods do not start |
| Locker Aurora writer down | writes fail until failover | as "locker down" for new cards |

## Metrics and alerts

Metrics: `http_server_requests_total{service="locker"}` and the card-vault metrics on port 9091.

| Alert | Condition | Severity | Runbook |
|---|---|---|---|
| `LockerErrorRateHigh` | 5xx share of locker requests above 1% over 5 minutes | critical | [locker-error-rate-high](../../runbooks/application/locker-error-rate-high.md) |
| `RetryBudgetExhausted` (`router-locker`) | router retry budget to the locker used up | critical | [retry-budget-exhausted](../../runbooks/application/retry-budget-exhausted.md) |
| `PanDetectedInLogs` | a PAN pattern seen in telemetry | security | security runbooks |

## Where in the repo

| Path | What |
|---|---|
| `vendor/card-vault` | Upstream card vault code and migrations |
| `docker/locker/Dockerfile` | Image |
| `deploy/charts/locker/` | Chart and its README (Vault paths, network rules) |
| `deploy/charts/payments-locker/` | Umbrella: locker plus `locker-migrations` |
| `deploy/envs/<env>/<region>/locker/values.yaml` | Database host, KMS alias, security group per region |
| `infra/live/<env>/eu-central-1/locker/` | Locker Aurora and its data access |
