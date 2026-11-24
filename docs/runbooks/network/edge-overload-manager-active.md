# EdgeOverloadManagerActive

Layer network, service edge, severity critical, owner platform-oncall, failure mode `network-edge-overload-manager-active`.
Dashboard: https://grafana.payments.internal/d/edge

## Symptom

The Envoy overload manager of a gateway pod is in the `stop_accepting_requests` action: the pod rejects new requests of every class, payments included.

## Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=EdgeOverloadManagerActive`) runs the read-only step of SSM document `pay-runbook-edge-overload-manager-active` and gathers metrics, events and sanitized logs.
2. Check which pod reports the action (`pod` label of the alert) and whether the other gateway pods are healthy.
3. Check the gateway pod memory and CPU against its limits and the number of open connections.
4. Check `LoadSheddingActive` for the same time: the class limit should shed before the overload manager acts.

## Actions

1. Scale the gateway out (document step `scale-gateway`) so that the load per pod falls below the overload threshold.
2. Restart a pod only if its memory is stuck above the threshold with low traffic (document step `restart-gateway-pod`, one pod at a time).
3. Do not raise the overload thresholds during the incident.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-edge-overload-manager-active`), which is audited.

## Escalation

Platform primary owns it; payments-core is informed. Page the incident commander at once if every gateway pod reports the action. Default chain: primary acknowledges within 5 min, the secondary is paged at 5 min and the incident commander at 15 min (section 20.6).

## SSM document

`pay-runbook-edge-overload-manager-active`
