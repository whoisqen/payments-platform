---
name: psp-connector-ops
description: Operational requirements for adding or changing a PSP connector.
---

# psp-connector-ops

- Egress: add the connector domains to the Network Firewall allowlist; mTLS where the PSP supports it.
- Timeouts per PSP profile (typically 15 s for authorization); a timeout is not a failure: the payment becomes the unknown state and scheduler runs sync.
- Idempotency: send our unique reference id to the PSP so a repeated call cannot charge twice; never retry a charge automatically.
- Retry on another PSP only for errors that prove no charge happened (for example a PSP 5xx before authorization).
- Circuit breaker per PSP x payment method; separate connection pool per PSP (bulkhead).
- Daily reconciliation of PSP reports against PostgreSQL; secret in Secrets Manager; feature flag, off by default.
