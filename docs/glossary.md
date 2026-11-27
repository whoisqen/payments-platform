# Glossary

Use the canonical term. `/glossary-check` flags the terms in the last column when they appear in a diff.

## Payments

New to card payments? Read [Payments in 10 minutes](architecture/domain/README.md) first; each row links to the section that explains the term with an example.

### Parties

| Term | Meaning | Do not call it |
|---|---|---|
| customer | A person who pays a merchant with their card (the cardholder) ([primer](architecture/domain/README.md#who-is-who)) | user (for a customer), buyer |
| merchant | A client store of the platform and its tenant: own `merchant_id`, API keys, PSP accounts and data ([primer](architecture/domain/platform-concepts.md#tenants-and-merchants)) | client, shop |
| payment orchestrator | A layer between merchants and many PSPs that stores, routes and tracks payments; this platform, built on Hyperswitch ([primer](architecture/domain/README.md#who-is-who)) | |
| PSP (connector) | The payment service provider the router sends a payment to; the connector is the router code that speaks its API ([primer](architecture/domain/platform-concepts.md#connectors)) | gateway (for a PSP), acquirer, bank |
| acquirer | The merchant's bank that receives card payments for it; reached through the PSP, never directly ([primer](architecture/domain/README.md#who-is-who)) | PSP |
| card network | The scheme (Visa, Mastercard) that carries requests between acquirers and issuers and sets their rules ([primer](architecture/domain/README.md#who-is-who)) | |
| issuer | The customer's bank that issued the card and approves or declines each authorization ([primer](architecture/domain/README.md#who-is-who)) | |

### Payment lifecycle

| Term | Meaning | Do not call it |
|---|---|---|
| payment / payment attempt | A payment (payment intent) is the intent to pay, created by `POST /payments`; an attempt is one call to a PSP (one payment can have several attempts) ([primer](architecture/domain/payment-lifecycle.md#payment-intent-and-payment-attempt)) | transaction, order |
| payment status | The `status` the router returns for a payment, a snake-case Hyperswitch `IntentStatus` such as `requires_capture` or `succeeded` ([primer](architecture/domain/payment-lifecycle.md#payment-statuses)) | |
| authorization | The issuer's approval that reserves the amount on the customer's account without moving it ([primer](architecture/domain/payment-lifecycle.md#authorization)) | |
| 3-D Secure | The issuer's check that the customer owns the card (bank app or one-time code); status `requires_customer_action` meanwhile ([primer](architecture/domain/payment-lifecycle.md#3-d-secure)) | |
| capture | Turning an authorization into a charge, automatic (in the confirm call) or manual (`POST /payments/{payment_id}/capture`) ([primer](architecture/domain/payment-lifecycle.md#capture)) | settlement |
| void | Cancelling an authorization before capture, `POST /payments/{payment_id}/cancel`, status `cancelled` ([primer](architecture/domain/payment-lifecycle.md#void)) | refund |
| refund / partial refund | Returning all or part of a captured amount, `POST /refunds`; statuses `pending`, `succeeded`, `failed`, `review` ([primer](architecture/domain/payment-lifecycle.md#refund-and-partial-refund)) | |
| chargeback / dispute | Money taken back by the issuer at the customer's request; the dispute is the whole case the merchant accepts or challenges ([primer](architecture/domain/payment-lifecycle.md#chargeback-and-dispute)) | refund |
| settlement | The actual movement of money issuer to network to acquirer to merchant, usually days after capture; the platform does not move money ([primer](architecture/domain/payment-lifecycle.md#settlement)) | capture |
| reconciliation | The daily comparison of platform records with each PSP's report; alert `ReconciliationMismatch` ([primer](architecture/domain/payment-lifecycle.md#reconciliation)) | |
| webhook | An HTTP notification of a change: PSP to router (incoming) or scheduler to merchant (outgoing, with `event_id`) ([primer](architecture/domain/payment-lifecycle.md#webhooks)) | |
| idempotency key | The `Idempotency-Key` header on every write; a repeat with the same key gets the first answer, kept 24 hours ([primer](architecture/domain/payment-lifecycle.md#idempotency-keys)) | |
| authorization rate | Share of successful authorizations among all attempts ([primer](architecture/domain/platform-concepts.md#authorization-rate)) | success rate, conversion |
| unknown state | A payment after a PSP timeout whose status is resolved by sync ([primer](architecture/domain/payment-lifecycle.md#why-a-charge-is-never-retried)) | pending, failed |
| sync | A status request to the PSP by our reference id ([primer](architecture/domain/payment-lifecycle.md#why-a-charge-is-never-retried)) | retry, re-check |

### Cards and compliance

| Term | Meaning | Do not call it |
|---|---|---|
| PAN / token | The full card number / its replacement from the locker; swapping one for the other is tokenization ([primer](architecture/domain/cards-and-compliance.md#tokenization-and-the-locker)) | card number, card id |
| BIN | The first 6 or 8 digits of a PAN, naming the issuer, network and card type; not secret on its own ([primer](architecture/domain/cards-and-compliance.md#the-parts-of-a-card)) | |
| CVV | The 3 or 4 digit security code on the card; passed through for one authorization, never stored ([primer](architecture/domain/cards-and-compliance.md#the-parts-of-a-card)) | |
| locker | The card vault; the only component that stores a PAN; shared by all cells ([primer](architecture/domain/cards-and-compliance.md#tokenization-and-the-locker)) | |
| PCI DSS | The card networks' security standard for anyone who stores, processes or transmits card data ([primer](architecture/domain/cards-and-compliance.md#pci-dss-in-plain-words)) | |
| CDE | Cardholder data environment: the accounts and components that see card data ([primer](architecture/domain/cards-and-compliance.md#the-cde-and-why-it-is-isolated)) | PCI zone, secure zone |
| masking | Showing at most the BIN and the last four digits of a PAN, for example `411111******1111` ([primer](architecture/domain/cards-and-compliance.md#what-may-and-may-not-be-logged)) | |
| SAQ / RoC | The two ways to prove PCI DSS compliance: a self-assessment questionnaire, or a report on compliance by an external assessor ([primer](architecture/domain/cards-and-compliance.md#saq-and-roc)) | |

### Merchant configuration

| Term | Meaning | Do not call it |
|---|---|---|
| profile | A separately configured business of one merchant with its own PSP accounts, routing and webhook address ([primer](architecture/domain/platform-concepts.md#profiles)) | |
| merchant connector account | One merchant's account at one PSP under a profile: connector, credentials, enabled payment methods ([primer](architecture/domain/platform-concepts.md#merchant-connector-accounts)) | |
| dummy connector | Hyperswitch's built-in fake PSP (`fauxpay`, `pretendpay`, `phonypay`, `stripe_test`, `dummy`); the only connector the live smoke test accepts ([primer](architecture/domain/platform-concepts.md#the-dummy-connector)) | |
| routing | The choice of connector for a payment: `single`, `priority`, `volume_split` or `advanced` rules, plus a circuit breaker per PSP ([primer](architecture/domain/platform-concepts.md#routing)) | |

### Data path

| Term | Meaning | Do not call it |
|---|---|---|
| write-behind | The router keeps payment state in key-value storage and the drainer writes it to PostgreSQL in batches; router never writes to PostgreSQL on the hot path | |
| drain lag | Time from the write to the Redis stream to the row in PostgreSQL | replication lag |
| drain lag SLO | p99 of the drain lag under 5 s; alert when the Redis stream length exceeds 50,000 | |

## Platform

| Term | Meaning | Do not call it |
|---|---|---|
| cell | An independent copy of the stack (EKS cluster, router, drainer, scheduler, MemoryDB, Aurora) serving a share of the merchants; four working cells in stage and prod, cell-0 only in dev ([primer](architecture/domain/platform-concepts.md#cells)) | |
| spare cell | The fifth cell without merchants, kept in a minimal profile and raised to the prod profile to take a hot merchant ([primer](architecture/domain/platform-concepts.md#the-spare-cell)) | |
| edge | The `payments-edge` Gateway and its Envoy proxies: TLS, request class, rate limits, routing to the cell named in the request ([primer](architecture/domain/platform-concepts.md#the-edge-and-request-classes)) | |
| request class | `payments`, `read` or `list`, set at the edge by path and method; decides the order of load shedding ([primer](architecture/domain/platform-concepts.md#the-edge-and-request-classes)) | |
| load shedding | Refusing requests under overload, lists first, reads next, payments last ([primer](architecture/domain/platform-concepts.md#load-shedding)) | |
| admin entry | The internal Gateway on the private zone that serves the admin tools after Okta sign-in | |
| central cluster | The EKS cluster in shared-services that runs metrics, logs, traces, Grafana, Alertmanager and Sentry outside the CDE | |
| size window | The `size_window` of `infra/live/stage/env.hcl`: `scheduled` runs stage at the dev sizes, `prod-size` is a booked test window at the prod sizes | |
| slow request | A request over the threshold of its type (status 50 ms; create, confirm, capture, refund 1,150 ms total; others 300 ms) | |
| generator | A script in `tools/config/` or `observability/` that writes files from config; its `--check` mode fails on hand edits | |
| SLO | Service level objective: a target over 30 days for authorization availability, overhead latency, status reads and webhooks ([primer](architecture/domain/platform-concepts.md#slos-for-a-business-reader)) | |
| overhead latency | The time the platform adds on top of the PSP's own time; SLO p99 under 150 ms ([primer](architecture/domain/platform-concepts.md#slos-for-a-business-reader)) | |
| error budget | (1 - SLO) x 43,200 minutes over 30 days ([primer](architecture/domain/platform-concepts.md#slos-for-a-business-reader)) | |
| environment | dev, stage, prod, pr-N | staging, production in resource names |
| promotion | Moving a digest to the next environment through a PR | release, deploy (for a promotion) |
| runbook | The instruction for an alert or an operation in `docs/runbooks/` | playbook (reserved for Ansible) |

## Regions and recovery

| Term | Meaning | Do not call it |
|---|---|---|
| working region | The only region that accepts writes: Frankfurt (eu-central-1) | |
| recovery region | The standby region: us-east-1, in prod only; stage and dev have none | |
| hot standby | The us-east-1 setup of prod: the cells run at the working size all the time (same clusters, node pools, replicas and MemoryDB, one Aurora instance per global secondary with the writer class of its working cluster) and take the whole load at any moment ([ADR-0019](adr/0019-hot-standby-recovery-region.md)) | warm standby, pilot light (rejected alternatives of ADR-0019) |
| region switch | Moving the traffic and writes of prod from the working region to the us-east-1 hot standby: fencing, Aurora promotion, cache warm-up, traffic move | |
| standby promotion | Making the us-east-1 Aurora instance of each global secondary the writer and allowing DynamoDB writes there during a region switch; `promotion` alone means moving a digest | |
| game day | A planned, announced region switch of prod to the hot standby and back, run quarterly with on-call approval | |
| fence | The drop rule in the `psp-fence` Network Firewall rule group that stops the old working region from reaching PSPs | |
| failback | The planned return to Frankfurt after it is rebuilt, approved by a person | |

## CI

| Term | Meaning | Do not call it |
|---|---|---|
| runner pool | An Auto Scaling group of self-hosted runner instances for one kind of job (`ci-build`, `ci-test`, `ci-light`, `ci-pr`) | |
| ci-pr pool | The runner pool for pull request jobs: no role to assume, no registry access, no cache write | |
| plan role / apply role | GitHub OIDC roles: the plan role reads only; an apply role per component trusts only `main` and `release/*` | |

Resource naming: `<prefix>-<env>-<region-short>-<component>`, for example `pay-prod-euc1-router` or `pay-prod-use1-aurora-cell-0`. Region short codes: `euc1`, `use1`, `glob`.
