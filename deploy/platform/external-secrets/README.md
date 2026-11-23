# External Secrets

External Secrets Operator (2 replicas) with two ClusterSecretStores.

- `values.yaml`: values of the upstream `external-secrets` chart, version `2.15.0`, pinned in `deploy/argocd/templates/addons/external-secrets.yaml`; not vendored (pin lives in the ApplicationSet).
- `config/`: chart `external-secrets-config` with the stores `aws-secrets-manager` (pod identity role, no static keys) and `vault` (Kubernetes auth role `external-secrets`), plus NetworkPolicies with default deny. It needs its own ArgoCD source (handoff to the argocd owner).
- Placeholders: `REPLACE_ESO_ROLE_ARN` in `values.yaml`; region, role ARN and CIDRs in `config/values.yaml`. Set `requireResolved: true` in the environment layer.
- Restrict a store to namespaces with `namespaceSelector`; the CDE cell should select only its own namespaces.
- No secret value is stored here: `ExternalSecret` objects of each cell name keys only.
- Break-glass access to the secrets themselves follows `deploy/platform/vault/README.md`; the operator role has read-only access and no human assumes it.
