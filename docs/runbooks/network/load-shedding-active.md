# LoadSheddingActive

Layer network, service edge, severity critical, owner platform-oncall, failure mode `network-load-shedding-active`.
Dashboard: https://grafana.payments.internal/d/edge

## Symptom

The edge returns 429 for the payments class because the traffic is above the capacity of the gateway (2000 RPS per pod). Lists and reports are shed first, then status polling above 1 per second; payments are the last class, so this means the gateway is past its limit.

## Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=LoadSheddingActive`) runs the read-only step of SSM document `pay-runbook-load-shedding-active` and gathers metrics, events and sanitized logs.
2. Check the edge dashboard: limited requests per class and per top-5 merchant. One merchant at the top means a hot merchant, not a capacity problem.
3. Compare gateway pod count and CPU with the HPA maximum; check whether a sale pre-scale (KEDA cron) ran.
4. Check `MerchantShareOfCellHigh` and `RateLimitHitsMerchant`: if they fire, follow `rate-limit-warnings`, section `merchant-share-of-cell-high`.
5. Check the authorization SLO burn; shedding that keeps payments served must not burn it.

## Actions

1. Scale the gateway: raise the HPA minimum of the ingress gateway (document step `scale-gateway`); the Helm values of `payments-edge` stay the source of truth, so follow with a pull request.
2. If one merchant causes it, raise or lower its override in its tenant file in Git (see `rate-limit-warnings`, section `rate-limit-hits-merchant`); do not lift the class limit.
3. Do not disable the local rate limit: the gateway then fails with 5xx instead of 429.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-load-shedding-active`), which is audited.

## Escalation

Platform primary owns it; payments-core is informed. Call the incident commander when payments are shed for more than 10 minutes. Default chain: primary acknowledges within 5 min, the secondary is paged at 5 min and the incident commander at 15 min (section 20.6).

## SSM document

`pay-runbook-load-shedding-active`
