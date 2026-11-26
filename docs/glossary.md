# Glossary

Use the canonical term. `/glossary-check` flags the terms in the last column when they appear in a diff.

## Payments

| Term | Meaning | Do not call it |
|---|---|---|
| merchant | A client store of the platform (tenant) | client, shop |
| customer | A buyer at a merchant | user (for a customer), buyer |
| PSP (connector) | The payment service provider the router sends a payment to | gateway (for a PSP), acquirer, bank |
| payment / payment attempt | A payment is the intent to pay; an attempt is one call to a PSP (one payment can have several attempts) | transaction, order |
| authorization rate | Share of successful authorizations among all attempts | success rate, conversion |
| CDE | Cardholder data environment: the accounts and components that see card data | PCI zone, secure zone |
| PAN / token | The full card number / its replacement from the locker | card number, card id |
| locker | The card vault; the only component that stores a PAN; shared by all cells | |
| unknown state | A payment after a PSP timeout whose status is resolved by sync | pending, failed |
| sync | A status request to the PSP by our reference id | retry, re-check |
| write-behind | The router keeps payment state in key-value storage and the drainer writes it to PostgreSQL in batches; router never writes to PostgreSQL on the hot path | |
| drain lag | Time from the write to the Redis stream to the row in PostgreSQL | replication lag |
| drain lag SLO | p99 of the drain lag under 5 s; alert when the Redis stream length exceeds 50,000 | |

## Platform

| Term | Meaning | Do not call it |
|---|---|---|
| cell | An independent copy of the stack (EKS cluster, router, drainer, scheduler, MemoryDB, Aurora) serving a share of the merchants; four working cells | |
| spare cell | The fifth cell without merchants, kept in a minimal profile and raised to the prod profile to take a hot merchant | |
| edge | The `payments-edge` Gateway and its Envoy proxies: TLS, request class, rate limits, routing to the cell named in the request | |
| request class | `payments`, `read` or `list`, set at the edge by path and method; decides the order of load shedding | |
| load shedding | Refusing requests under overload, lists first, reads next, payments last | |
| admin entry | The internal Gateway on the private zone that serves the admin tools after Okta sign-in | |
| central cluster | The EKS cluster in shared-services that runs metrics, logs, traces, Grafana, Alertmanager and Sentry outside the CDE | |
| slow request | A request over the threshold of its type (status 50 ms; create, confirm, capture, refund 1,150 ms total; others 300 ms) | |
| generator | A script in `tools/config/` or `observability/` that writes files from config; its `--check` mode fails on hand edits | |
| error budget | (1 - SLO) x 43,200 minutes over 30 days | |
| environment | dev, stage, prod, pr-N | staging, production in resource names |
| promotion | Moving a digest to the next environment through a PR | release, deploy (for a promotion) |
| runbook | The instruction for an alert or an operation in `docs/runbooks/` | playbook (reserved for Ansible) |

## Regions and recovery

| Term | Meaning | Do not call it |
|---|---|---|
| working region | The only region that accepts writes: Frankfurt (eu-central-1) | |
| recovery region | A region that receives data and backups continuously: us-east-1 (warm standby) and us-east-2 (data and backups only) | |
| warm standby | The compute, MemoryDB and Aurora readers kept running in us-east-1 for stage and prod; it serves no traffic until the region switch | |
| region switch | Moving traffic and writes from the working region to the warm standby (automatic) or to us-east-2 (plan B) | |
| standby promotion | Making the us-east-1 Aurora secondaries writers and allowing DynamoDB writes there during a region switch; `promotion` alone means moving a digest | |
| fence | The drop rule in the `psp-fence` Network Firewall rule group that stops the old working region from reaching PSPs | |
| failback | The planned return to Frankfurt after it is rebuilt, approved by a person | |

## CI

| Term | Meaning | Do not call it |
|---|---|---|
| runner pool | An Auto Scaling group of self-hosted runner instances for one kind of job (`ci-build`, `ci-test`, `ci-light`, `ci-pr`) | |
| ci-pr pool | The runner pool for pull request jobs: no role to assume, no registry access, no cache write | |
| plan role / apply role | GitHub OIDC roles: the plan role reads only; an apply role per component trusts only `main` and `release/*` | |

Resource naming: `<prefix>-<env>-<region-short>-<component>`, for example `pay-prod-euc1-router` or `pay-prod-use1-aurora-cell-0`. Region short codes: `euc1`, `use1`, `use2`, `glob`.
