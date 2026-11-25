# identity-center

Human access to AWS through IAM Identity Center in the management account. Okta is the IdP: SAML sign-in with MFA, users and groups pushed by SCIM, so this module resolves names (`DisplayName`, `UserName`) and never creates principals.

- Permission sets: `Admin` (management only, PT1H), `PlatformAdmin` (member accounts, no audit tampering), `SRE-View` (every account via `sre_view_groups`; EKS access entries use `AWSReservedSSO_SRE-View`), `ReadOnly` (no data-plane reads), `Billing`, `SRE-CDE` (PowerUser with audit deny, PT1H, never standing).
- Standing access: `assignments` = account => permission set => groups; validations reject Admin outside management and any standing SRE-CDE.
- JIT: `cde_jit_grants` (account in `cde_accounts`, one group or user, `expires_at` RFC 3339, `reason`); a precondition rejects an expiry in the past or more than 1 h after the plan.
- Flow: a PR adds the grant to `config/access/cde-jit-grants.yaml`, a second SRE approves, the merge apply assigns SRE-CDE. A scheduled job (every 15 min) applies with `CDE_JIT_REVOCATION_RUN=true`, which destroys expired assignments, and opens a PR removing the expired entries (until then normal plans fail on them).
- Revocation lags by up to the schedule interval; an open session keeps working until its PT1H ends. The quarterly review (PCI DSS 7.2.4) reads `standing_assignments`.
- Outputs: `permission_set_arns`, `standing_assignments`, `active_cde_grants`. Agents never apply this stack.
