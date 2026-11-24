# Sentry (self-hosted, central cluster, outside the CDE)

Error tracking for the platform services. Deployed by `deploy/argocd/templates/addons/central/sentry.yaml` into namespace `sentry` of the cluster labelled `payments-platform/central: enabled`: chart `sentry` 36.1.0 (`values.yaml`), chart `clickhouse` 9.4.4 (`clickhouse-values.yaml`, Snuba event store), and `manifests/` (ExternalSecret, PodDisruptionBudgets, PostgreSQL primary service). The URL is `central.sentry_url` in `config/platform.yaml`.

## Secrets

`tools/config/render_sentry.py` generates `manifests/externalsecret.yaml`. Create these in AWS Secrets Manager as `<naming.prefix>/shared-services/sentry/<name>`: `system-secret-key`, `admin-password`, `postgres-password`, `postgres-replication-password`, `redis-password`, `clickhouse-password`, `launchpad-rpc-secret`. Nothing secret is in git; the system secret key must never change after the first start.

## Card data

Sentry must never hold a PAN. Three layers:

1. SDKs: `send_default_pii=false` (`sendDefaultPii: false`), no request bodies, no local variables, `before_send` drops `payment_method_data`, `card`, `cvv` fields.
2. Server defaults (`values.yaml`): scrub data, scrub defaults and scrub IP addresses required for every organization; session replay off.
3. Advanced scrubbing: after the first start, as the admin, apply `pii-config.json` (PAN-like digit runs, CVV fields, `@creditcard`) to the organization and turn the scrubber on:

```
curl -X PUT -H "Authorization: Bearer $SENTRY_TOKEN" -H "Content-Type: application/json" \
  "$SENTRY_URL/api/0/organizations/<org>/" \
  -d "$(jq -n --rawfile c pii-config.json '{dataScrubber: true, dataScrubberDefaults: true, scrubIPAddresses: true, sensitiveFields: ["card","pan","cvv","cvc","expiry"], relayPiiConfig: $c}')"
```

Apply the same `relayPiiConfig` to a project that overrides it. Check with a test event containing `4111 1111 1111 1111`: it must show `[PAN]`.

## Projects and DSNs

Create one organization and one project per service (router, drainer, scheduler, locker, control-center) in the UI or `POST /api/0/teams/<org>/<team>/projects/`. The DSN of a project is under Settings, Client Keys; use the public URL host (relay serves `/api/<id>/`). Put each DSN into Secrets Manager as `<naming.prefix>/<env>/sentry/<service>-dsn`; External Secrets in the service cluster reads it. Application charts are not changed here.

Hyperswitch (`vendor/`) is not changed: it needs the Sentry SDK enabled in its code or through a setting of its own, if the release has one; until then the DSN secrets are unused.

## Not covered

Ingress class, TLS issuer and a shared `ReadWriteMany` storage class (`efs`) for the filestore are assumed for the central cluster. Images are the chart's tags, not digests. PostgreSQL and Redis replicas give read copies, not automatic failover.
