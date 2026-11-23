# deploy

Helm and ArgoCD: `charts/` (charts), `envs/<env>/<region>/<cell>/` (values), `platform/` (add-ons), `argocd/` (AppProjects, ApplicationSets).

Argo CD AppProjects and ApplicationSets are the chart `deploy/argocd`; install with `helm template argocd deploy/argocd -f <(tools/config/argocd-values.py) | kubectl apply -f -` (values come from `config/platform.yaml`).
