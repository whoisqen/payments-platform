# Handoff: warm standby region, terraform-engineer to k8s-engineer

What exists now (stage only, `standby_enabled = true`): per cell in `infra/live/stage/us-east-1/<cell>` the stacks eks, karpenter, memorydb, iam-workloads and Aurora readers; routing in `infra/live/stage/eu-central-1/edge-dns-routing`.

What `deploy/` must add:
- ApplicationSet destinations for the us-east-1 clusters: `<prefix>-stage-use1-<cell>` (same pattern as `<prefix>-<env>-euc1-<cell>`, region short from the region name).
- `deploy/envs/stage/us-east-1/values.yaml` (CIDRs) and `cell-*/values.yaml` (Aurora reader and MemoryDB endpoints, known after apply).
- The public ingress name per region (`config/platform.yaml` `deploy.stage.ingress_endpoints`) once the Istio gateways exist.
