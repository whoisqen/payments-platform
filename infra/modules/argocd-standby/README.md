# argocd-standby

Lets Argo CD core run in the first standby cell cluster of us-east-1 when the shared-services Argo CD in eu-central-1 is gone.
Creates `<prefix>-<env>-use1-argocd-standby`, an IRSA role of `argocd/argocd-application-controller` on the host cluster, and an
access entry for it on every standby cluster (AmazonEKSAdminPolicy, the namespaces of the argocd entry of env.hcl).
`installer_role_arn` grants cluster-admin on the host cluster only, for the install of the chart; apply again with null to revoke it.
Test: `terraform init -backend=false && terraform test`.
