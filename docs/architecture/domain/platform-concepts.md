# Platform concepts

The words this platform uses for its own building blocks, explained for someone who knows what a card payment is (see [Payments in 10 minutes](README.md)) but not how an orchestrator is organised. The infrastructure behind each concept is in the [architecture overview](../README.md).

## Tenants and merchants

A **merchant** is a business that uses the platform to take payments; it is the platform's tenant. Each merchant has a `merchant_id`, its own API keys, its own PSP accounts and its own data, and never sees another merchant's payments. Example: a ticket seller with `merchant_id` `tickets_eu` signs up, gets a secret API key for its servers and a publishable key for its payment page.

Hyperswitch has a further layer above merchants, also called a tenant, meant for running several independent platforms on one deployment. This platform runs one such Hyperswitch tenant (`public`) for all of its merchants, so in these docs "tenant" always means a merchant.

## Profiles

A **profile** (business profile) splits one merchant into separately configured businesses. Each profile has its own PSP accounts, routing rules, webhook address and return URL. Example: the ticket seller runs one profile for its EU site and one for its UK site, each with its own PSP and its own webhook endpoint. Every payment belongs to one profile; the smoke test passes `profile_id` when it creates its payment.

## Connectors

A **connector** is the code in the router that speaks one PSP's API: it turns the router's "authorize 1000 EUR" into the PSP's request format and the PSP's answer back into a router status. Hyperswitch ships connectors for many PSPs, so adding a PSP is usually configuration, not new code. In these docs PSP and connector name the same thing from two sides: the company, and the integration with it.

### Merchant connector accounts

A **merchant connector account** (MCA) is one merchant's account at one PSP, stored in the router: which connector, the merchant's credentials at that PSP, which payment methods and currencies are enabled, and the profile it belongs to. Example: the ticket seller's EU profile has one MCA for PSP A with cards in EUR and one for PSP B as a fallback. The credentials are encrypted in the router's database and never logged.

### The dummy connector

The **dummy connector** is a fake PSP built into Hyperswitch that answers like a real one without moving money. It comes under several names (`fauxpay`, `pretendpay`, `phonypay`, `stripe_test` and the plain `dummy`), and test cards make it approve or decline on demand. The live smoke test that runs after every deployment uses it and refuses to run against any other connector, so a smoke test can never charge a real card.

## Routing

**Routing** decides which PSP gets a payment. A profile carries a routing algorithm:

| Type | What it does | Example |
|---|---|---|
| `single` | Always the same connector. | The smoke test pins `{"type": "single", "data": "<dummy connector>"}`. |
| `priority` | An ordered list; the first available connector wins. | PSP A, then PSP B. |
| `volume_split` | Shares by percentage. | 80% PSP A, 20% PSP B while PSP B is being tried out. |
| `advanced` | Rules on payment fields. | Amounts over 500 EUR or cards with a given BIN go to PSP B. |

On top of the rules the platform watches PSP health. A circuit breaker per PSP and payment method moves traffic to the fallback PSP when technical errors pass a threshold, and the `PspCircuitBreakerOpen` alert tells the on-call engineer. Routing never turns a failed charge into a second charge: another PSP is tried only after an error that proves no money was taken (see [why a charge is never retried](payment-lifecycle.md#why-a-charge-is-never-retried)).

## Cells

A **cell** is a complete, independent copy of the payment stack: its own Kubernetes cluster, router, drainer, scheduler, MemoryDB and Aurora database. The platform runs four working cells (`cell-0` to `cell-3`), and every merchant lives in exactly one of them. A table in DynamoDB maps `merchant_id` to its cell, and the edge sends each request to the cell named in the request's `x-payments-cell` header.

Why split at all:

- **Size.** The busiest moments (a sale peak) need more database capacity than one database should carry. Four cells share the load at roughly a quarter each.
- **Blast radius.** A bad rollout or an exhausted database hurts at most the merchants of one cell, about a quarter, not all of them.
- **Safe rollouts.** A new version reaches `cell-0` first, which carries internal and test merchants, then the other cells one at a time, each watched before the next.

The locker is the one shared piece: it serves all cells, because a card belongs to the customer, not to one merchant.

### The spare cell

The **spare cell** is a fifth cell with no merchants, kept small and cheap. When one merchant grows so large that it crowds out its neighbours (more than 30% of a cell's load raises the `MerchantShareOfCellHigh` alert), operators raise the spare cell to full size and move that merchant there with `scripts/cells/migrate-merchant.py`. The move copies the merchant's data, pauses its writes for a short moment and switches its row in the cell map.

## The edge and request classes

The **edge** is the front door: the `payments-edge` Gateway, a set of Envoy proxies that every API request passes before it reaches a router. It terminates TLS, applies rate limits and sends the request to the merchant's cell.

The edge also gives each request a **request class** by its path and method, because not all requests are equally urgent:

| Class | Requests | Example |
|---|---|---|
| `payments` | Everything that creates or changes something. | `POST /payments`, `POST /payments/{payment_id}/confirm`, `POST /refunds` |
| `read` | Reading one object. | `GET /payments/{payment_id}` |
| `list` | Lists, searches and reports. | `/payments/list`, `/refunds/list`, `/reports` |

## Load shedding

**Load shedding** is refusing some requests on purpose when the platform is overloaded, so that the important ones still get through. The edge sheds by request class: lists first, reads next, payments last. A refused request gets `429` with `Retry-After`, so the caller knows when to try again.

The reasoning is business, not technical: a monthly report can be fetched five minutes later at no cost, but a customer standing at a checkout will leave. Separately, each merchant has its own rate limit, so one merchant's traffic spike cannot take the capacity of the others. Details are in [rate limiting and load shedding](../runtime/rate-limiting.md).

## SLOs for a business reader

An **SLO** (service level objective) is a promise about how well the platform works, stated as a number over 30 days. The **error budget** is how much failure the promise allows; while budget is left, the team ships changes, and when it is spent, reliability work comes first.

| SLO | Target | In plain words |
|---|---|---|
| Authorization availability | 99.99% of `confirm` calls without a 5xx error on our side | At most about 4 minutes a month of payment failures caused by the platform. Declines by the issuer and errors of a PSP that the platform passed on or routed around do not count: we answer for our code, not for the bank. |
| Platform overhead latency | p99 under 150 ms, met 99.9% of the time | The time the platform adds on top of the PSP's own time. The PSP and the issuer may take a second or two; our share stays under 150 ms for 99 payments out of 100. |
| Payment status read | p99 under 50 ms, 99.95% | `GET /payments/{payment_id}` answers almost instantly. |
| Outgoing webhook | delivered within 60 s, 99.9% | The merchant hears about a result within a minute. |

**Overhead latency** is measured as our time only, because a customer's wait is mostly the PSP and the issuer, which the platform cannot speed up; what it can do is not add to them.

### Authorization rate

The **authorization rate** is the share of payment attempts that the issuer approves. It is the number a merchant cares about most: every point lost is sales lost. It depends mostly on the issuers and PSPs, not on the platform, so it is watched rather than promised:

- dashboards show it per platform, per cell and per PSP;
- an alert fires when a PSP's rate falls 5 points below the same time a week ago, a sign that routing should move traffic elsewhere;
- a canary rollout that lowers it is stopped before it reaches more cells, and a chaos test stops when it drops by more than 2 points.
