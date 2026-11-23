# arc

Actions Runner Controller on the shared-services cluster.
- `deploy/argocd/templates/addons/arc.yaml`: controller, three scale sets (ci-prod, ci-stage, ci-pr) and `config/`; apps are independent, so retry with backoff covers CRD and namespace ordering.
- `values-*.yaml`: upstream chart values; runner images are digest placeholders; ci-prod runs on NodePool `ci-prod` (taint `workload=ci-prod`), the others on `ci`.
- `config/`: namespaces, PriorityClasses, service accounts, per-scale-set ExternalSecrets (one GitHub App key each), quotas, NetworkPolicies.
- Assumes External Secrets Operator 0.17+ (`external-secrets.io/v1`) and NodePools `ci` and `ci-prod` defined by the karpenter module.
- Replace every `REPLACE_*` value before sync; no secrets live here.
