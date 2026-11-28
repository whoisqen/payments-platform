# Day-2 operations

This page covers the work that follows the first rollout: adding a cell, moving merchants, rotating secrets, upgrading EKS and scaling. The first deployment is in [deploy.md](deploy.md). Alerts have their own runbooks, listed at the end.

Every change below goes through a pull request. Infrastructure is applied dev first, then stage, then prod (see [How applies run](deploy.md#4-how-applies-run)).

## Adding a cell

A cell is a full copy of the payment stack: an EKS cluster, Aurora, MemoryDB and workload roles. The `spare` cell already exists and takes hot merchants. Add a new cell only when the capacity model asks for one ([capacity](../../capacity/README.md)).

### 1. Infrastructure

1. Add the cell to `cells` and `kms_keys` in `infra/live/<env>/env.hcl`.
2. Copy the units of an existing cell into the new cell's directory. The cell name comes from the path, so the files need no edit.
   - working region: `infra/live/<env>/eu-central-1/<cell>/{eks,karpenter,argocd-registration,data-access,aurora,memorydb,iam-workloads,endpoint}`;
   - prod us-east-1 (hot standby): the same units under `infra/live/prod/us-east-1/<cell>/`; the `aurora` unit there joins the global cluster of the working region.
3. Add the new cell's `eks` to the dependencies of the units that list every cell cluster: `analytics/msk-access`, `locker/data-access` and `locker/endpoint`.
4. Add the cell name to the allowed `cell` tag values in `policy/tagging/schema.yaml` and `policy/scp/tag-policies/required-tags.json`.
5. Apply from the environment directory. `terragrunt run --all -- apply` picks up the new units in dependency order.

### 2. Kubernetes

1. Create `deploy/envs/<env>/eu-central-1/<cell>/values.yaml` from another cell's file. Set `global.cell`, the Aurora and MemoryDB endpoints, and `routerGateway.targetGroupArn` from the `target_group_arn` output of the cell's `endpoint` unit.
2. Add the cell to `routing.cells` in `deploy/envs/<env>/eu-central-1/edge/values.yaml`, so the edge can route to it.
3. Run `python3 tools/config/render_standby.py`. It writes the recovery-region files under `deploy/envs/<env>/<standby region>/` from the working region's cells.
4. Add the cell to a step of the RollingSync in `deploy/argocd/templates/applicationset-cells.yaml`. If the new cell is now the last step, point `dispatchCell` in `deploy/platform/smoke/notifications/values.yaml` at it.
5. Run `python3 tools/config/render_vault.py` and apply the Argo CD values again (`tools/config/argocd-values.py`). Both read the cluster list from the live tree (`tools/config/render/clusters.py`), so the new `eks` unit gets its Argo CD cluster Secret and its Vault jwt auth mount `k8s-<cluster name>` without a hand-kept list ([deploy.md, section 9](deploy.md#9-argo-cd-bootstrap)).
6. Vault:
   1. In a break-glass session, run `sh /workloads/workloads.sh` on the central Vault: it writes the per-environment policies and the jwt mount and roles of the new cluster from its registration secret ([Vault README](../../../deploy/platform/vault/README.md)).
   2. Write the cell's secrets under `secret/<env>/<cell>/` ([secret paths](deploy.md#secrets-the-externalsecrets-expect)).

### 3. Moving merchants

`scripts/cells/migrate-merchant.py` moves one merchant between cells in four steps:

1. Copy the data.
2. Freeze the merchant's writes for a short window.
3. Copy what changed in the meantime and verify it.
4. Switch the route in the DynamoDB merchant-to-cell table.

It is idempotent per `--run-id`, so a re-run with the same id continues where the last run stopped. Run with `--dry-run` first:

```sh
python3 scripts/cells/migrate-merchant.py --merchant <merchant_id> --source-cell cell-1 --target-cell spare \
  --run-id <uuid> --name-prefix <prefix> --region eu-central-1 --dry-run
```

The script stops safely in two cases:

- **The freeze takes too long.** The limit is `--max-freeze-s`, 120 seconds by default. The script exits with code 2.
- **The copy does not match.** The script exits with code 3.

In both cases the merchant stays in the source cell.

## Rotating secrets

| Secret | How to rotate | When the new value takes effect |
|---|---|---|
| Database passwords (Vault `secret/<env>/<cell>/<service>/database`, `secret/<env>/locker/database`) | Write a new Vault version, update the RDS Proxy secret to the same value, then restart the cell workloads. | Pods read variables at start only, so after the restart. |
| Other Vault values (`shared/app`, `shared/locker`, locker keys, Redis passwords) | Write a new Vault version, then restart the workloads that read it. | External Secrets refreshes within 1 hour; the pods after their restart. |
| Secrets Manager values (`pay/<env>/...`, `pay/shared-services/...`) | `aws secretsmanager put-secret-value` from a terminal. | External Secrets refreshes within 1 hour. |
| KMS keys | Nothing to do: every customer managed key rotates yearly. | Automatic. |
| Vault unseal and recovery keys | Follow the break-glass procedure in the [Vault README](../../../deploy/platform/vault/README.md#break-glass): two custodians, one audited session. | At once. |
| GitHub App keys, the notifications token | Create a new key or token, update the repository secret or `pay/shared-services/argocd/notifications`, then revoke the old one. | The next workflow run. |

Restart workloads through Argo CD, with the Restart action on the Deployment or Rollout. Restart one cell at a time, `cell-0` first. Vault records every read and write in its audit device.

## Upgrading EKS

Clusters move one Kubernetes minor version at a time. Every environment runs the same version.

1. Raise `kubernetes_version` by one minor version in `infra/live/<env>/env.hcl` and `infra/live/shared-services/env.hcl`. Raise `bottlerocket_version` to the Bottlerocket version built for that Kubernetes version.
2. Check that the pinned add-on charts support the new version. Their versions are pinned in `deploy/argocd/templates/addons/`.
3. Plan the environment with `make plan ENV=<env>`.
4. Apply the `eks` unit, then the `karpenter` unit, of one cell at a time: `cell-0` first, the `spare` cell last.
   - The `eks` apply upgrades the control plane. Managed add-ons that are not pinned take the default version of the new Kubernetes version. The bootstrap node group follows the control plane.
   - The `karpenter` apply sets the new Bottlerocket alias in the node classes. Karpenter treats that as drift and replaces the nodes. PodDisruptionBudgets limit how many pods move at once.
5. Upgrade the `locker`, `edge`, `control-center` and `analytics` clusters and the central cluster (`shared-services/eu-central-1/central/eks`, `central/karpenter`) the same way.
6. Wait until every Application is Healthy and the SLO dashboards are green before you upgrade the next environment.

Repeat for dev, then stage, then prod. In prod, upgrade the us-east-1 hot-standby clusters right after their eu-central-1 counterparts, so both regions always run the same version.

## Scaling

| What | Where | Notes |
|---|---|---|
| Pods of a service | `autoscaling` in the chart values, overridden in `deploy/envs/<env>/values.yaml` | HPA on CPU by default (router: 20 to 90 replicas at 70% CPU). `kind: keda` switches a service to a KEDA ScaledObject. |
| Nodes | `eks.cpu_limits` per pool (`payments`, `stateful`, `cde`, `workers`) in `config/environments/<env>.yaml` | Karpenter CPU caps per pool. `eks.spot_pools` lists the pools that may use Spot. The `cde` pool never does, and prod lists none. |
| Aurora | `aurora.writer_class`, `aurora.reader_class`, `aurora.reader_count` | A class change restarts the instance, so apply it one cell at a time. |
| MemoryDB | `memorydb.node_type`, `memorydb.shards` | Resharding is online. |
| Analytics | `msk`, `analytics_eks` in `config/environments/<env>.yaml`; defaults in the `analytics` block of `infra/live/<env>/env.hcl` | MSK volumes never shrink. |
| Stage size | `size_window` in `infra/live/stage/env.hcl` | `"prod-size"` books a load or region switch test window at prod size; `"scheduled"` returns to the dev sizes. |
| More merchants than the cells hold | a new cell, then merchant moves | See [Adding a cell](#adding-a-cell). |

`prod.yaml` is the reference for sizes. `dev.yaml` and `stage.yaml` list only what they change.

Dev Aurora clusters stop outside working hours (`aurora-schedule`). To work outside the window, start a cluster with `aws rds start-db-cluster --db-cluster-identifier <prefix>-dev-euc1-aurora-<cell>`. A stopped cluster starts by itself after seven days.

## Region switch and standby compute

In a region switch of prod, traffic and writes move from eu-central-1 to us-east-1. The standby clusters, node pools and MemoryDB already run at full size, so nothing is built:

1. `dr-failover` fences the old region and promotes the running us-east-1 Aurora instance of each global cluster.
2. Route 53 moves the API traffic; the switch runbook flips the active Global Accelerator endpoint group.
3. Terraform runs against the us-east-1 state replica with `PAY_STATE_REGION=us-east-1` until failback.

Standby sizes live in `standby` of `config/environments/prod.yaml`; prod keeps `standby.compute_enabled: true`.

The procedure and the drills are in [failover](../../dr/failover.md) and [drills](../../dr/drills.md). The on-call steps are in the [promote standby region runbook](../../runbooks/meta/promote-standby-region.md).

## Runbooks

Every alert links to one runbook under `docs/runbooks/<layer>/`. Each layer except `slo` also has a `warnings.md` for its warning-level alerts.

| Layer | Directory | Examples |
|---|---|---|
| Application | [runbooks/application](../../runbooks/application/) | synthetic payment failing, drain lag, locker errors, PSP degraded |
| Compute | [runbooks/compute](../../runbooks/compute/) | crash loops, Karpenter cannot launch nodes |
| Data | [runbooks/data](../../runbooks/data/) | Aurora writer unavailable, MemoryDB memory, central logs and Logstash |
| Network | [runbooks/network](../../runbooks/network/) | region down, certificates, load shedding, Route 53 health checks |
| Backup and DR | [runbooks/backup-dr](../../runbooks/backup-dr/) | Aurora global lag, backup and restore test failures |
| Security and PCI | [runbooks/security-pci](../../runbooks/security-pci/) | Vault sealed, break-glass use, PAN in logs, GuardDuty findings |
| SLO | [runbooks/slo](../../runbooks/slo/) | authorization availability, webhook delivery, overhead latency |
| Meta | [runbooks/meta](../../runbooks/meta/) | Alertmanager notifications failing, promote the standby region |
