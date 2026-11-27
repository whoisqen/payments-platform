# Namespaces Argo CD deploys to, taken from the destinations of deploy/argocd/templates; the argocd access entry of every cluster lists them.
# A namespace-scoped AmazonEKSAdminPolicy cannot create CRDs, cluster roles or namespaces: those parts of the add-ons need a Kubernetes RBAC grant of their own.
locals {
  # Add-ons with payments-platform/addons: enabled (cert-manager, external-secrets, istio, karpenter, kube-prometheus, kyverno, otel-collector, exporters).
  addons = ["cert-manager", "external-secrets", "istio-system", "istio-ingress", "kube-system", "kyverno", "monitoring"]

  # Cells, locker, edge and control-center: the ApplicationSets (payments, payments-edge, control-center), ratelimit (gated) and the load generator.
  workload = concat(local.addons, ["payments", "payments-edge", "control-center", "ratelimit", "k6-operator", "loadgen"])

  analytics = local.addons
}
