# Grafana: accounts and access

Grafana (central cluster, outside the CDE) knows people only through the identity provider (OIDC). `access.yaml` is generated from `config/platform.yaml` (`access.grafana_groups`) by `tools/config/render_grafana.py`; edit the config, not the file.

## Who gets what

| IdP group (default name) | Grafana role | What the person can do |
|---|---|---|
| `pay-grafana-admins` | Grafana server admin + org Admin | Everything, including users and settings. A few people. |
| `pay-sre` | Editor | All dashboards, **Explore** (metrics, logs, traces), silences of alerts. |
| `pay-security` | Editor | The same, for investigations. |
| `pay-engineering` | Viewer | All dashboards, read only. |
| `pay-finance` | Viewer | The same (the FinOps dashboard is among them). |
| `pay-audit` | Viewer | The same, for assessors. |
| any other person | none | Cannot log in (`role_attribute_strict`). |

A person in several groups gets the strongest role. Dashboards are provisioned from the repository and cannot be changed in the UI (`allowUiUpdates: false`); Viewers and Editors cannot share snapshots or embed Grafana outside. Raw logs and traces are reachable only through Explore, so only Editors and Admins see them; card numbers are masked before data leaves the cluster.

## Creating and removing accounts

- **Create:** put the person into the IdP group. The account is created at the first login (`allow_sign_up` of the OAuth login only; the local sign-up is off) with the role of the group. Nothing is done in Grafana.
- **Change the role:** move the person to another group; the role is recomputed at every login.
- **Remove:** take the person out of the group (or disable the account in the IdP). A running session ends within 24 hours (`login_maximum_lifetime_duration`), an idle one after 8; to cut it off at once, revoke the sessions in the IdP and delete the user in Grafana (Administration, Users).
- **Break-glass:** the local `admin` user comes from the secret `<prefix>/shared-services/grafana/admin` and logs in at `/login/local` (the login form is hidden). Use it only when the IdP is down, and rotate the secret afterwards.
- **Automation:** use Grafana service accounts with an expiring token, kept in Secrets Manager (`<prefix>/shared-services/grafana/sa-<name>`); no personal API keys, no shared logins.

## Limits of this setup

The open-source Grafana has no team sync from the IdP and no folder or data source permissions by group (both are Enterprise features). Access is therefore by role, not by folder: everyone with a role sees every dashboard. If a dashboard must be hidden from some people, either move it to a separate Grafana instance or buy Enterprise (team sync and RBAC) and replace the role mapping with teams.

## Before the first login

Create the six groups in the IdP (names in `access.grafana_groups`), make the IdP send them in the `groups` claim of the ID token, and fill the client id, secret and endpoints in the secret `<prefix>/shared-services/grafana/oidc`.
