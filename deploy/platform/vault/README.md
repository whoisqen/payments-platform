# Vault

HA Vault (3 pods, one per AZ, Raft storage, KMS auto-unseal) in `shared-services`.

- `values.yaml`: values of the upstream `hashicorp/vault` chart, version `0.34.1`, pinned in `deploy/argocd/templates/addons/vault.yaml`. The chart is not vendored: a `file://` dependency is impossible, so the pin lives in the ArgoCD ApplicationSet.
- `config/`: chart `vault-config` with the NetworkPolicies (default deny, explicit rules) and the hourly snapshot CronJob. It needs its own ArgoCD source (handoff to the argocd owner); the upstream chart has no hook for extra objects.
- Per-environment values, all `REPLACE_*` here: `REPLACE_KMS_KEY_ID`, `REPLACE_AWS_REGION`, `REPLACE_VAULT_ROLE_ARN`, `REPLACE_VAULT_VERSION`, `REPLACE_VAULT_IMAGE_DIGEST` in `values.yaml`; bucket, KMS key, role ARN, image and CIDRs in `config/values.yaml`. Set `requireResolved: true` in the environment layer so a leftover placeholder fails the render.
- The snapshot bucket (replicated to both recovery regions), its KMS key and the pod identity roles come from Terraform; this directory only consumes their names.
- Namespace `vault` must carry `pod-security.kubernetes.io/enforce: restricted` (set by the namespace owner).
- Vault side configuration (kubernetes auth roles `vault-snapshot` and `external-secrets`, policies, audit device) is applied after initialisation by the Vault bootstrap, not by this chart. Initial unseal keys are never used: KMS unseals, recovery keys are split and held offline.

## Break-glass

- No human holds standing Vault access: the `root` token is revoked after bootstrap and no static admin policy is bound to a person.
- Access is requested through the IdP (OIDC, MFA required), approved by a second person, and granted as a Vault policy with a TTL of at most 1 hour that cannot be renewed.
- Every login, token creation and secret read is written to the audit device (file on `auditStorage`, shipped to the central log store); a break-glass use opens an incident that is reviewed within one working day.
- If OIDC is down, a root token is generated from the offline recovery keys by at least two custodians, used for one session, and revoked at once; the event is recorded the same way.
