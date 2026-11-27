# deploy

Helm and ArgoCD: `charts/` (charts), `envs/<env>/<region>/<cell>/` (values), `platform/` (add-ons), `argocd/` (AppProjects, ApplicationSets).

Argo CD AppProjects and ApplicationSets are the chart `deploy/argocd`; install with `helm template argocd deploy/argocd -f <(tools/config/argocd-values.py) | kubectl apply -f -` (values come from `config/platform.yaml`).

Clusters register through the same chart: each entry of `clusters` (environment, region, component, labels) renders an ExternalSecret that turns the Terraform secret `<namePrefix>/argocd/clusters/<namePrefix>-<env>-<region short>-<component>` (`{name, server, caData, roleARN}`) into an Argo CD cluster Secret with IAM authentication, the add-on labels and the EKS name in the annotation `payments-platform/eks-cluster-name`. The cluster Argo CD runs in is an entry with `inCluster: true`, a plain Secret without credentials, so it exists before External Secrets is installed; the ExternalSecrets apply once its CRDs are there (repeat the apply).
