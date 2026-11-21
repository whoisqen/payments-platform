---
name: helm-chart
description: Create or change a Helm chart on the platform-common library chart.
---

# helm-chart

- Use named templates from `platform-common`: probes, PDB (`maxUnavailable: 10%`), HPA or KEDA ScaledObject, default-deny NetworkPolicy, ServiceMonitor, securityContext (non-root, read-only root filesystem, no capabilities), topologySpreadConstraints across 3 AZs.
- Native sidecar: `istio-proxy` as an init container with `restartPolicy: Always`.
- Ship `values.schema.json` (reject typos, wrong types, `maxReplicas` below `minReplicas`) and helm-unittest tests; `image.digest` must match `^sha256:[a-f0-9]{64}$`.
- Values layers: chart defaults, environment, region, cell, `images.yaml` (CI-owned).
- Checks: `helm lint --strict`, `helm template` + `kubeconform`, Conftest/Kyverno on the render, `ct install` on kind.
