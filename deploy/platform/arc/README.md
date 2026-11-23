# arc

Actions Runner Controller on the shared-services cluster. Jobs from every workflow share one queue per scale set; nothing outranks anything else. Capacity follows the queue: ARC adds runner pods for waiting jobs and Karpenter adds the nodes, then drops empty nodes after 2 minutes.

| Scale set (`runs-on`) | For | Node pool | Instances | Warm / max | Runner request |
|---|---|---|---|---|---|
| `ci-build` | cargo and image builds, trusted code | `ci-build` | arm64 `c7gd` 4xlarge to 8xlarge, NVMe, On-Demand | 1 / 8 | 14 CPU, 26 GiB |
| `ci-build-amd64` | amd64 image build, trusted code | `ci-build-amd64` | x86 `c7id` 2xlarge to 4xlarge, NVMe, On-Demand | 0 / 2 | 7 CPU, 13 GiB |
| `ci-test` | unit, chart and policy tests | `ci-test` | arm64 `m7g` xlarge to 2xlarge, Spot or On-Demand | 1 / 16 | 3 CPU, 12 GiB |
| `ci-light` | lint, commit checks, plan, promotion | `ci-light` | arm64 `m7g` large to xlarge, Spot or On-Demand | 1 / 20 | 1.5 CPU, 5 GiB |
| `ci-pr` | every job of pull request code | `ci-pr` | arm64 `c7g` xlarge to 4xlarge, Spot or On-Demand | 1 / 20 | 3 CPU, 12 GiB |

- What a job may do comes from the service account of its scale set (cache write, image pull, plan role); `ci-pr` is untrusted: its own nodes, no role, private ranges denied, no ECR, no secrets.
- Only the two build namespaces allow the privileged `dind` sidecar that `docker buildx` needs; they run trusted code on nodes of their own.
- Build nodes use local NVMe as ephemeral storage (RAID0), so layers, the cargo target directory and the sccache working set never touch EBS.
- `minRunners` keeps one idle runner per pool so a job starts without waiting for a node; raise it if the queue time of a pool is above 30 s, lower it to 0 to save cost.
- Files: `deploy/argocd/templates/addons/arc.yaml` (controller, one Application per scale set from `arc.scaleSets`, and `config/`), `values-<scale set>.yaml` (upstream chart values; runner images are digest placeholders), `config/` (namespaces, service accounts, one ExternalSecret per scale set, quotas, limit ranges, NetworkPolicies).
- Assumes External Secrets Operator 0.17+ (`external-secrets.io/v1`) and the node pools of the karpenter module (`enabled_pools`).
- Replace every `REPLACE_*` value before sync (role ARNs and secret keys are outputs of `infra/modules/ci-runners`); no secrets live here.
