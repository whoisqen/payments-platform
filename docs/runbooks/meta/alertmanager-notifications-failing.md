# AlertmanagerNotificationsFailing

Layer meta, service alertmanager, severity critical, owner observability-oncall, failure mode `meta-alertmanager-notifications-failing`.
Dashboard: https://grafana.payments.internal/d/platform-overview

## Symptom

Alertmanager fails to send notifications to an integration.

## Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=AlertmanagerNotificationsFailing`) runs the read-only step of SSM document `pay-runbook-alertmanager-notifications-failing` and gathers metrics, events and sanitized logs.
2. Read the Alertmanager log for the receiver and the HTTP error.
3. Check the secret files of the receiver and the status page of the provider.

## Actions

1. Fix the credential or the network path; verify with a test alert from the on-call tool.
2. Use the phone bridge of the incident commander while the integration is down.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-alertmanager-notifications-failing`), which is audited.

## Escalation

Page the commander through the secondary channel: the failing integration cannot carry this alert. Default chain: primary acknowledges within 5 min, the secondary is paged at 5 min and the incident commander at 15 min (section 20.6).

## SSM document

`pay-runbook-alertmanager-notifications-failing`
