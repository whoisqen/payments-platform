# argocd-access

IAM side of Argo CD reaching clusters in other accounts.
- `hub` (shared-services): role `<prefix>-shared-services-argocd-controller` for `argocd/argocd-application-controller` and `argocd/argocd-server` (Pod Identity on the central cluster), allowed to assume every spoke role; role `<prefix>-shared-services-argocd-registration` that the eks stacks assume to write `<prefix>/argocd/clusters/*`.
- `spoke` (dev, stage, prod): role `<prefix>-<env>-argocd-controller` trusted by the hub controller role only; the cluster access entries are its grants.
Apply order: central eks, hub, then each spoke before the eks stacks of its environment.
Test: `terraform init -backend=false && terraform test`.
