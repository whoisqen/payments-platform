# tests/load

k6 scenarios (open model, `ramping-arrival-rate`) with the 7-calls-per-payment weights; target is the dummy PSP connector, never real money.

- `lib/`: profiles (TPS to RPS, mix, stages), thresholds from the SLOs, request builders, k6 glue.
- `scenarios/`: smoke, average (160 TPS), daily-peak (480), sale-peak (1,430), stress (2,860), breakpoint.
- `mock-psp/`: Node mock PSP with configurable latency, error and timeout rates.
- Offline proof: `npm test` (node:test, no k6); syntax: `node --check scenarios/*.js lib/*.js`.
- Run: `k6 run -e BASE_URL=... -e MERCHANT_API_KEY=... -e TEST_PAYMENT_TOKEN=... scenarios/sale-peak.js`; 10,000+ RPS needs k6 Cloud load zones.
