# Cards and compliance

What card data is, why it is dangerous to hold, and how the platform keeps it in one small, locked place. The controls themselves are listed in [security controls](../../security/README.md); this page explains the reasons behind them.

## The parts of a card

| Part | What it is | Example | Rule on this platform |
|---|---|---|---|
| **PAN** (primary account number) | The 15 to 19 digit number on the front of the card. It identifies the card account; with the expiry date it is often enough to pay online. | `4111 1111 1111 1111` is a well-known test PAN. | Lives only in the locker, encrypted. Never in logs, metrics, traces or analytics. |
| **BIN** (bank identification number, also IIN) | The first 6 or 8 digits of the PAN. They name the issuer, the card network, the country and the card type (debit, credit, prepaid). | `411111` in the test PAN above points to a Visa card. | Not secret on its own; useful for routing and fraud rules. |
| **CVV** (also CVC, the security code) | The 3 or 4 digit code on the card. It proves the card is physically in the customer's hands. | `123` | Passed through for one authorization and never stored, not even in the locker. |
| **expiry date** | Month and year after which the card stops working. | `12/29` | Encrypted at rest; never logged. |

Why the PAN matters so much: anyone who has it, with the expiry date, can try to pay with someone else's money. A database full of PANs is the most valuable thing an attacker can steal from a payments company, so the whole design is about keeping that database tiny and closed.

## Tokenization and the locker

**Tokenization** replaces the PAN with a **token**: a random reference that means nothing outside this platform. The token can be stored, logged as an id, sent between services and handed to the merchant; stealing it gives an attacker nothing to pay with.

The **locker** (card vault) is the one service that does the swap:

1. The router receives card details when a payment is confirmed.
2. It sends them to the locker over mutual TLS. The locker accepts calls from the router identity only.
3. The locker encrypts the card with its own KMS key, which no other role can use, stores it in its own Aurora database and returns a token.
4. Everything after that (the payment record, the stream, the drainer, PostgreSQL, analytics, webhooks) carries the token, never the PAN.
5. When a PSP needs the real card, the router fetches it from the locker for that one call and does not keep it.

A saved card is the same mechanism: a returning customer pays with a `payment_token` instead of typing the card again. The smoke test confirms its payment this way.

The locker is shared by all cells because a card belongs to the customer, not to one merchant: the same customer may pay several merchants that live in different cells.

## PCI DSS in plain words

**PCI DSS** (Payment Card Industry Data Security Standard) is the rule book that the card networks require from anyone who stores, processes or transmits card data. It is a contract condition, not a law: a company that breaks it can lose the right to accept cards and pay for any fraud that follows a leak.

In plain words it asks for twelve groups of things, among them:

- keep card data only where needed and encrypt it where it is stored;
- never store the CVV after authorization;
- encrypt card data on every network hop;
- restrict who and what can reach card data, with named accounts and multi-factor sign-in;
- log every access and keep the logs safe from tampering;
- scan, patch and test the systems regularly;
- have a written incident response.

The cost of PCI DSS grows with every system that touches card data, because each one must meet all of the rules. That is why the platform keeps the number of such systems as small as it can.

## The CDE and why it is isolated

The **CDE** (cardholder data environment) is every system that stores, processes or transmits card data, plus everything that can reach those systems. On this platform it is the router, the locker, the drainer, the scheduler and their data stores. Each of their resources carries the `pci-scope` tag.

Isolation keeps the CDE small, and a small CDE is both safer and cheaper to audit:

- **Fewer places to steal from.** A PAN exists only in the locker; the rest of the CDE sees tokens.
- **Fewer systems in the audit.** The control center, analytics (MSK, ClickHouse, OpenSearch), CI and monitoring run outside the CDE, so they are not held to every CDE rule. This works only because nothing card-related flows to them.
- **Hard walls.** CDE workloads run on their own tainted node pool, network policies deny all traffic unless allowed, Istio requires mutual TLS, and outbound calls leave only through a firewall that admits PSP domains. People get CDE access just in time, for at most an hour, after a second engineer approves it.

## What may and may not be logged

Logs, metrics and traces leave the CDE for the central observability cluster, so they must never carry card data.

| May be logged | May not be logged |
|---|---|
| `payment_id`, `refund_id`, `merchant_id` in log lines | PAN, full or partial beyond the masked form |
| Status, amount, currency, connector name, error class | CVV, in any form |
| A masked PAN: at most the BIN and the last four digits, for example `411111******1111` | Expiry date or cardholder name next to a PAN |
| HTTP status codes and timings | Tokens, API keys, `Authorization` headers, idempotency keys |

**Masking** means replacing the middle digits of a PAN with `*` so a person can recognise a card ("the Visa ending in 1111") without being able to use it. PCI DSS allows showing at most the BIN and the last four digits.

Several layers enforce this, so one mistake is not enough to leak a PAN: `Secret<T>` wrappers in the Rust code hide values from debug output, the Semgrep rule `no-pan-logging` blocks code that logs card fields, the OpenTelemetry collector in each cluster deletes card fields and high-cardinality ids from telemetry before it leaves, Sentry scrubs events, and Macie scans the CDE's S3 buckets daily. A PAN found in logs raises a security alert with its own runbook.

## SAQ and RoC

PCI DSS compliance is proven in one of two ways, depending mainly on how many card payments a company handles each year:

- **SAQ** (self-assessment questionnaire): the company answers a questionnaire about its own controls. Smaller merchants use it. A merchant that sends cards to this platform's payment page and never sees a PAN usually qualifies for one of the shorter SAQs, because the card data never touches its systems.
- **RoC** (report on compliance): an external assessor (a QSA) audits the controls on site and writes a report. Large merchants and service providers that store cards for others are expected to produce one.

This page gives the context only; the controls the platform runs and the evidence it keeps are in [security controls](../../security/README.md) and the [threat model](../../security/threat-model.md).
