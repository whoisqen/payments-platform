# Smoke after sync

- `job/`: chart with the PostSync Job of one cell; added as the last source of the `payments-cells` ApplicationSet, so prod and `cde-*` (gated) never get it.
- `notifications/`: `argocd-notifications-cm` and its ExternalSecret, replacing the ones of the argo-cd chart (`argocd-values.yaml` sets `cm.create` and `secret.create` to false).

## Secrets

- `<prefix>/<env>/smoke/dummy-connector` (per cell cluster), JSON keys: `api_key`, `merchant_id`, `profile_id`, `connector` (the dummy connector), `payment_method_token`. Never real card data.
- `<prefix>/shared-services/argocd/notifications` (Argo CD cluster), JSON keys: `github-dispatch-url` (`https://api.github.com/repos/<owner>/<repo>/dispatches`), `github-dispatch-token`, `alertmanager-url` (`https://<alertmanager>/api/v2/alerts`).
- The token is a fine-grained personal access token limited to this one repository with `Contents: Read and write` (the permission `repository_dispatch` needs; `Metadata: Read` is implied). A GitHub App installation token expires after an hour and does not fit a static header.

## Behaviour

- Green: sync Succeeded and health Healthy of the `spare` Application of dev or stage sends `smoke-green-<env>`; `spare` is the last RollingSync step and exists in every environment (dev runs only `cell-0` and `spare`). Payload: `environment`, `app`, `cell`, `revisions`.
- Failed sync or smoke: an alert to Alertmanager only, nothing to GitHub.
