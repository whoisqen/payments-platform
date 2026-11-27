# okta-sso

Sign-in of the administrators to every admin tool through Okta (OIDC, authorization code flow with PKCE).

- Six Okta groups from `access.grafana_groups` (one per role); the members of the administrator group are `admin_user_ids` (two, the owner and a reserve). Everyone else is placed in the other groups in Okta, not here.
- One OIDC application per entry of `apps` (Grafana, Argo CD, Vault, the proxy of Alertmanager, VictoriaMetrics and Prometheus, Sentry). All six groups are assigned to each application, nobody directly. The `groups` claim carries only these six names (exact regex).
- One sign-in policy `admin-tools` for all applications: two factors on every sign-in, a phishing-resistant factor and re-authentication every 2 hours for the administrators, 12 hours for the others. After the first apply check in Okta that the catch-all rule of the policy denies.
- One secret per application, `<prefix>/shared-services/<tool>/oidc`, encrypted with the shared key: `client_id`, `client_secret`, `auth_url`, `token_url`, `api_url`, `issuer`. The ExternalSecrets of the tools read them. The client secrets are also in the state, which is KMS-encrypted.
- The Okta provider takes its API token from `OKTA_API_TOKEN` in the environment of the apply role; the live unit sets only the organization. Agents never apply this stack.
- Rotation: set `client_secret_rotation = { <app> = "<new id>" }` (for example the date) in the live unit; the apply creates a new application before it deletes the old one and writes the new client id and secret to the same Secrets Manager secret; roll the tool once External Secrets has synced. Rotate yearly and after any suspected exposure. Outputs: `group_ids`, `client_ids`, `oidc_secret_arns`, `endpoints`.
