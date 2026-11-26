# Payment lifecycle

What happens to a payment from the moment a merchant creates it until the money is settled, refunded or disputed. Each step names the API call and the status the router returns. Start with [Payments in 10 minutes](README.md) if the parties (merchant, PSP, acquirer, issuer) are new to you.

## Payment intent and payment attempt

A **payment intent** is the merchant's statement "this customer will pay this amount". The merchant creates it with `POST /payments`, for example `{"amount": 1000, "currency": "EUR", "capture_method": "automatic"}` for 10.00 EUR. The router returns a `payment_id` and the status `requires_payment_method`. No money has moved and no PSP has been called.

A **payment attempt** is one call to one PSP for that payment. A payment can have several attempts: if the first PSP declines before any money is reserved, the merchant can try again and the router records a second attempt under the same `payment_id`. The glossary calls the intent simply a **payment**.

## Authorization

**Authorization** is the question "may this card pay this amount?" sent to the issuer. The merchant (or the payment page) confirms the payment with `POST /payments/{payment_id}/confirm` and a payment method, for example a card token. The router sends it to a PSP, which passes it through the acquirer and the card network to the issuer.

- Approved: the issuer reserves the amount on the customer's account. The money is held, not yet moved.
- Declined: insufficient funds, a blocked card, a fraud suspicion. The payment ends as `failed`; the merchant may ask the customer for another card, which becomes a new attempt.

A reservation does not last forever. If it is not captured in time, the issuer releases it and the router reports `expired`.

## 3-D Secure

**3-D Secure** (3DS) is an extra check where the issuer asks the customer to prove they own the card, usually in the bank's app or with a one-time code. In Europe strong customer authentication makes it common for online card payments.

A payment asks for it with `"authentication_type": "three_ds"` (or `no_three_ds`). While the customer is on the bank's page the payment is in `requires_customer_action`; the payment page redirects the customer there and back. After a successful check, authorization goes on as usual. A payment that passed 3DS also shifts fraud liability: if the cardholder later says "that was not me", the issuer rather than the merchant usually carries the loss.

## Capture

**Capture** turns a reservation into a real charge. The `capture_method` of the payment decides when it happens.

| Capture method | When the money is taken | Example |
|---|---|---|
| `automatic` | Right after a successful authorization, in the same call. The payment goes straight to `succeeded`. | A concert ticket: the goods are delivered at once. The smoke test uses this. |
| `manual` | Later, when the merchant calls `POST /payments/{payment_id}/capture`. Until then the payment waits in `requires_capture`. | A hotel reserves 300.00 EUR at booking and captures the final bill at checkout. |

A manual capture may take less than was authorized: the hotel reserved 300.00 EUR and captures 240.00 EUR. The router then reports `partially_captured`, or `partially_captured_and_capturable` when the PSP allows more captures later (`manual_multiple`).

## Void

A **void** cancels an authorization that has not been captured, so the reservation is released and no money moves. The call is `POST /payments/{payment_id}/cancel`, and the payment becomes `cancelled`. Example: the hotel booking is cancelled before checkout. A void costs the customer nothing and is cheaper for the merchant than a refund, so it is the right tool whenever the payment is still `requires_capture`.

## Refund and partial refund

A **refund** returns money from a captured payment to the customer. It is a separate object with its own id: `POST /refunds` with `{"payment_id": "...", "amount": 500}` returns a `refund_id` and a refund status.

- A **partial refund** returns part of the amount: the smoke test pays 10.00 EUR and refunds 5.00 EUR. Several partial refunds may follow until the captured amount is used up.
- A refund only works on a payment that was captured (`succeeded` or partly captured). An uncaptured payment is voided instead.

| Refund status | Meaning |
|---|---|
| `pending` | Sent to the PSP, the final answer has not come yet. |
| `succeeded` | The PSP accepted the refund; the money is on its way back. |
| `failed` | The PSP refused the refund. |
| `review` | Held for manual review. |

The money reaches the customer's account days later, on the issuer's schedule.

## Chargeback and dispute

A **chargeback** is a refund forced by the issuer: the customer tells their bank "I did not make this payment" or "I never got the goods", and the bank takes the money back from the merchant through the card network. The merchant can accept the loss or send evidence (delivery proof, a signed contract) to fight it. The whole case is a **dispute**.

The router receives disputes from the PSP and keeps them as dispute objects with these statuses:

| Dispute status | Meaning |
|---|---|
| `dispute_opened` | The issuer opened the case; the merchant has a deadline to answer. |
| `dispute_challenged` | The merchant sent evidence. |
| `dispute_accepted` | The merchant accepted the loss. |
| `dispute_won`, `dispute_lost` | The network decided for or against the merchant. |
| `dispute_expired`, `dispute_cancelled` | The deadline passed without an answer, or the case was withdrawn. |

A dispute moves through stages (`pre_dispute`, `dispute`, `pre_arbitration`, `arbitration`); most cases end in the first two. Disputes are costly for a merchant beyond the amount itself, which is one reason 3-D Secure is worth its extra step.

## Settlement

**Settlement** is the moment money actually moves between banks. Authorization and capture are messages; settlement is the transfer. Once a day, typically, the issuer pays the card network, the network pays the acquirer, and the acquirer (or the PSP) pays the merchant the captured amounts minus fees. A payment that was `succeeded` on Monday may reach the merchant's bank account on Wednesday.

The platform does not hold or move money. It records what was authorized, captured and refunded, and the PSP settles with the merchant.

## Reconciliation

**Reconciliation** compares the platform's records with the PSP's own report, line by line, to prove both sides agree on every amount. The platform runs it as a daily job per PSP. When a payment's amount differs between the two, the `ReconciliationMismatch` alert fires and the on-call engineer follows the [reconciliation runbook](../../runbooks/application/warnings.md#reconciliation-mismatch).

Reconciliation is also what closes the gap after a region switch: the scheduler asks the PSP for the status of every recent payment by our reference id and restores records that did not reach the recovery region. See [disaster recovery](../../dr/README.md).

## Webhooks

A **webhook** is an HTTP call that tells the other side "something changed" instead of making it ask again and again. There are two directions.

- **Incoming, PSP to router.** The PSP reports late results: a refund that finished, a payment that left `processing`, a new dispute. The router de-duplicates them by the PSP's event id, so a webhook delivered twice changes the payment once.
- **Outgoing, platform to merchant.** The scheduler sends the merchant events such as `payment_succeeded`, `payment_failed`, `refund_succeeded` or `dispute_opened`. Each carries an `event_id`, so the merchant can ignore a repeat. A failed delivery is tried again with growing gaps (1 minute, 5 minutes, 30 minutes, 2 hours, 12 hours) before it is parked in a dead-letter queue. The SLO: 99.9% of webhooks delivered within 60 s of the event.

Merchants that poll `GET /payments/{payment_id}` more than once a second per payment get `429` with `Retry-After`; webhooks are the intended way to learn about changes.

## Payment statuses

The router returns one `status` per payment. The values are the Hyperswitch `IntentStatus` names in snake case.

| Status | Meaning | Typical next step |
|---|---|---|
| `requires_payment_method` | Created; no card or other method attached yet. | Confirm with a payment method. |
| `requires_confirmation` | A payment method is attached but the payment is not confirmed. | Confirm. |
| `requires_customer_action` | Waiting for the customer, usually on the 3-D Secure page. | The customer finishes the check. |
| `requires_merchant_action` | Waiting for the merchant, for example a manual fraud approval. | The merchant approves or rejects. |
| `processing` | The PSP has not given a final answer yet. | A webhook or a sync with the PSP updates it. |
| `requires_capture` | Authorized, money reserved, not yet captured (manual capture). | Capture or void. |
| `partially_authorized_and_requires_capture` | The issuer approved only part of the amount. | Capture the approved part or void. |
| `partially_captured` | Part captured; the rest can no longer be captured. | Refund if needed. |
| `partially_captured_and_capturable` | Part captured; more captures are allowed. | Capture again. |
| `partially_captured_and_processing` | Part captured; the PSP is still working on the rest. | Wait for a webhook or sync. |
| `succeeded` | Captured in full. Refunds and disputes are possible from here. | Refund if needed. |
| `failed` | Declined or failed. Nothing was charged. | The customer may try again: a new attempt. |
| `cancelled` | Voided before capture. | None. |
| `cancelled_post_capture` | Cancelled after capture. | None. |
| `expired` | The reservation lapsed before capture. | None. |
| `review` | Marked for manual review after an unexpected PSP answer, for example a capture that failed after it was reported successful. | The merchant resolves it, or a PSP webhook does. |
| `conflicted` | The amount or currency the PSP received differs from what the router sent. | Investigate with the PSP. |

The platform also uses the term **unknown state** for a payment whose PSP call timed out: the router cannot tell whether the issuer approved it. That is not a separate status value; it is resolved by sync, described below.

## Idempotency keys

An **idempotency key** is a unique string the merchant puts in the `Idempotency-Key` header of every request that changes something (create, confirm, capture, refund). If the same request arrives twice with the same key, the router returns the first answer instead of doing the work again. The key and the answer are kept for 24 hours.

Why it matters: networks fail. A merchant sends "confirm payment", the connection drops before the answer arrives, and the merchant does not know if the customer was charged. With an idempotency key it simply sends the same request again: if the first one went through, it gets the same `succeeded` back and nobody is charged twice. The smoke test does exactly this; its keys look like `smoke-<run>-confirm`.

The same idea applies one step further: the router sends each PSP call with our own unique reference id, so a PSP that receives the same call twice can recognise it.

## Why a charge is never retried

Retrying is normal for reads and dangerous for charges. If the router calls a PSP to authorize 10.00 EUR and gets no answer within the timeout (15 s for authorization), the money may or may not have been reserved. Sending the charge again could take 20.00 EUR from the customer.

So the platform does not retry a charge, ever, automatically:

- The PSP call is configured with no retries (`psp-authorize`: `max_attempts: 0` in `policy/resilience/policy.yaml`).
- The payment goes to the unknown state, and the scheduler runs a **sync**: it asks the PSP "what happened to the payment with our reference id?". A sync is a read, so it is safe to repeat, and it is retried with backoff until the PSP answers.
- Another PSP is tried only after an error that proves no charge happened, for example the PSP refusing the request before it reached the issuer.
- A merchant that repeats a request with the same idempotency key is safe for the reason above; a merchant that sends a new key creates a new charge on purpose.
