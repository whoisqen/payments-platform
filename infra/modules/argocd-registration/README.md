# argocd-registration

Argo CD registration of one EKS cluster: secret `<prefix>/argocd/clusters/<argocd_cluster_name>` in shared-services, written by the
`argocd-registration` unit next to each `eks` unit (its provider assumes `<prefix>-shared-services-argocd-registration`).
Value: JSON `name`, `server`, `caData`, `roleARN`, `clusterName` (EKS name for `awsAuthConfig`), `environment`, `region`.
Resource policy: only `reader_role_arn` (External Secrets of the central cluster) may read; the writer keeps read for refresh.
Test: `terraform init -backend=false && terraform test`.
