---
name: k6-scenario
description: Write a k6 scenario with the payment request weights, open model and thresholds.
---

# k6-scenario

- Open model: executor `ramping-arrival-rate`, so arrivals do not depend on response times.
- Weights follow the 7 calls per payment table: create 1, confirm 1, status 2, payment methods 1, inbound webhook 1, capture/refund/token 1.
- Use test merchants with the dummy PSP connector (300-1,500 ms delay); never real money.
- Thresholds: platform overhead p99 < 150 ms, status p99 < 50 ms, 5xx < 0.01% for load; `abortOnFail` for breakpoint.
