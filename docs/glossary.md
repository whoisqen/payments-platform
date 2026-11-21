# Glossary

Use the canonical term. `/glossary-check` flags the terms in the last column when they appear in a diff.

| Term | Meaning | Do not call it |
|---|---|---|
| merchant | A client store of the platform (tenant) | client, shop |
| customer | A buyer at a merchant | user, buyer |
| PSP (connector) | The payment service provider the router sends a payment to | gateway, acquirer, bank |
| payment / payment attempt | A payment is the intent to pay; an attempt is one call to a PSP (one payment can have several attempts) | transaction, order |
| authorization rate | Share of successful authorizations among all attempts | success rate, conversion |
| CDE | Cardholder data environment: the accounts and components that see card data | PCI zone, secure zone |
| PAN / token | The full card number / its replacement from the locker | card number, card id |
| unknown state | A payment after a PSP timeout whose status is resolved by sync | pending, failed |
| sync | A status request to the PSP by our reference id | retry, re-check |
| drain lag | Time from the write to the Redis stream to the row in PostgreSQL | replication lag |
| environment | dev, stage, prod, pr-N | staging, production in resource names |
| promotion | Moving a digest to the next environment through a PR | release, deploy |
| runbook | The instruction for an alert or an operation in `docs/runbooks/` | playbook (reserved for Ansible) |

Resource naming: `<domain>-<env>-<region-short>-<component>`, for example `pay-prod-euc1-router` or `pay-prod-euw1-aurora-payments`.
