# Grafana: accounts and access

Grafana (central cluster, outside the CDE) knows people only through the identity provider (OIDC). `access.yaml` is generated from `config/platform.yaml` (`access.grafana_groups`, `access.grafana_orgs`) by `tools/config/render_grafana.py`; edit the config, not the file.

## Who gets what

The open-source Grafana has no team sync and no folder permissions, so access is split by **organization**: every organization has its own dashboards and data sources, and a group is mapped to an organization and a role at login (`org_attribute_path` + `org_mapping`). The model is data in `config/platform.yaml` (`access.grafana_orgs`); `tools/config/render_grafana.py` turns it into `access.yaml` (grafana.ini, providers, data sources), one ConfigMap per organization and folder (`manifests/org-*.yaml`) and the bootstrap Job (`manifests/org-bootstrap.yaml`).

| IdP group (default name) | Organization (id) | Role | Dashboards |
|---|---|---|---|
| `pay-grafana-admins` | Main Org. (1) | Admin, and Grafana server admin | all |
| `pay-sre` | Main Org. (1) | Editor | all, plus **Explore** (metrics, logs, traces) and silences |
| `pay-security` | Main Org. (1) | Editor | all, plus Explore for investigations |
| `pay-engineering` | Engineering (2) | Viewer | L0 overview, L1 services, L2 platform |
| `pay-finance` | Finance (3) | Viewer | FinOps only |
| `pay-audit` | Audit (4) | Viewer | L0 overview and the compliance set: `backup`, `edge`, `dr-switch` |
| any other person | none | none | cannot log in |

A person in several groups is a member of each organization of those groups and switches between them in the profile menu. Dashboards are provisioned from the repository and cannot be changed in the UI (`allowUiUpdates: false`); Viewers and Editors cannot share snapshots or embed Grafana outside. Raw logs and traces are reachable only through Explore, which only the Main Org. Editors and Admins have; card numbers are masked before data leaves the cluster. The organizations other than the main one hold the VictoriaMetrics data source only (all dashboards use it).

How denial works: `allowed_groups` lists only the groups of wired organizations, so everyone else is refused at login; `role_attribute_strict` stays on; `auto_assign_org` is off, so nobody falls into the main organization by default. `role_attribute_path` names the main-organization groups only (and grants the server admin flag), so the other groups get their organization and role from `org_mapping` alone.

## Adding a group or an organization

Organizations cannot be created by file provisioning, and Grafana may refuse to start when a data source or provider names an organization that does not exist. Hence a fixed order, enforced by the generator (it refuses `provisioned: true` while the image is a placeholder and renders no Job without a real image):

0. Fill `access.grafana_bootstrap_image` (a Python 3 image, pinned by digest, signed like every image) in `config/platform.yaml`.
1. Add the group to `access.grafana_groups` (and the IdP, see below) and the organization to `access.grafana_orgs` with the next free `id`, `groups`, `dashboards` (`all`, or `folders` of `observability/dashboards` and single dashboards by `uid`), `datasources`, and `provisioned: false`. Run `python3 tools/config/render_grafana.py`. After the sync, the PostSync Job `grafana-org-bootstrap` creates the organization (idempotent; it never renames or deletes, and fails when an id or name does not match the config).
2. Check that the Job succeeded, then set `provisioned: true` and render again: now the providers, data sources, `org_mapping` and `allowed_groups` carry the organization. The groups of an organization that is not provisioned yet cannot log in (fail closed). Sessions that already exist keep their old access for up to 24 hours, and the old Main Org. membership of such a person is removed at the first login after the flip; to cut it sooner, remove the user from Main Org. in Administration.

To give an existing group more dashboards, edit `dashboards` and render; for a group of an existing organization only the IdP group is needed. Organization ids are append-only: never reorder, reuse or delete them (a deleted id is never handed out again, so a recreated organization would get another id). Before the first sync, or to see what the Job would do, run `bootstrap_orgs.py --orgs orgs.json --dry-run` (from `deploy/platform/grafana/scripts/`, with `GRAFANA_URL`, `GRAFANA_ADMIN_USER`, `GRAFANA_ADMIN_PASSWORD` in the environment, for example through a port-forward); the Job image is `access.grafana_bootstrap_image`.

## Creating and removing accounts

- **Create:** put the person into the IdP group. The account is created at the first login (`allow_sign_up` of the OAuth login only; the local sign-up is off) in the organization and with the role of the group. Nothing is done in Grafana.
- **Change the role:** move the person to another group; the role is recomputed at every login.
- **Remove:** take the person out of the group (or disable the account in the IdP). A running session ends within 24 hours (`login_maximum_lifetime_duration`), an idle one after 8; to cut it off at once, revoke the sessions in the IdP and delete the user in Grafana (Administration, Users).
- **Break-glass:** the local `admin` user comes from the secret `<prefix>/shared-services/grafana/admin` and logs in at `/login/local` (the login form is hidden). Use it only when the IdP is down, and rotate the secret afterwards.
- **Automation:** use Grafana service accounts with an expiring token, kept in Secrets Manager (`<prefix>/shared-services/grafana/sa-<name>`); no personal API keys, no shared logins.

## Limits of this setup

The open-source Grafana has no team sync and no folder or data source permissions by group (both are Enterprise features). Organizations hide dashboards, they do not isolate data: a Viewer can query every data source of their organization through the API, so the Finance organization can read every metric of VictoriaMetrics, not only the FinOps panels. If a metric must stay unreadable for a group, give that group a separate Grafana or a separate VictoriaMetrics tenant, or buy Enterprise (team sync and RBAC). Whether `role_attribute_strict` also accepts a person that `org_mapping` places but the role expression does not name (engineering, finance, audit) depends on the Grafana version; check it at the first login of each such group, and if they are refused, set `role_attribute_strict` to false in the generator (`allowed_groups` still denies everyone else).

## Identity provider: Okta

Grafana logs in through Okta over OIDC (authorization code flow with PKCE); the group names are sent in the `groups` claim.

1. In Okta create an *OIDC - Web Application* integration for Grafana with the grant type *Authorization Code*.
2. Sign-in redirect URI: `<dns.grafana_url>/login/generic_oauth`; sign-out redirect URI: `<dns.grafana_url>/login`.
3. Assign the six groups of `access.grafana_groups` to the integration; nobody is assigned directly.
4. Groups claim of the integration: name `groups`, included in the ID token, filter *Matches regex* `pay-.*`, so that no other group of the organization reaches Grafana.
5. Scopes: `openid profile email groups`.
6. Endpoints of the org authorization server: `https://<okta-domain>/oauth2/v1/authorize`, `/oauth2/v1/token`, `/oauth2/v1/userinfo`; they are the `auth_url`, `token_url` and `api_url` of the secret below.
7. **MFA is required.** Give the integration an authentication policy that demands two factors on every sign-in (a phishing-resistant factor for the administrators); Grafana does not ask for a second factor itself.
8. `pay-grafana-admins` has two members: the owner and one reserve administrator, so that access can be restored when one of them is unavailable.

## Before the first login

Create the six groups in the IdP (names in `access.grafana_groups`), make the IdP send them in the `groups` claim of the ID token, and fill the client id, secret and endpoints in the secret `<prefix>/shared-services/grafana/oidc`.
