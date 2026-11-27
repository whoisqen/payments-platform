# StageTestWindow

Layer compute (a procedure that no alert points to), service stage environment, owner platform-oncall.

## Symptom

A load, stress, spike or soak test needs stage at the prod size. By default stage runs `size_window = "scheduled"` in `infra/live/stage/env.hcl`: dev sizes for Aurora (`db.r7g.large`, no readers), MemoryDB (`db.t4g.small`, 1 shard) and the node pool caps. Analytics is small too (3 MSK brokers, one OpenSearch node). The cells and the spare have the same layout as in prod; stage has no standby region.

## Diagnostics

1. Book the window in the team calendar, with its start, end and purpose. Do not run two prod-size windows in parallel.
2. Check that no stage promotion is in flight. Resizing Aurora writers and MemoryDB causes short failovers.
3. Check EC2 Spot and on-demand capacity for the prod node pool caps in eu-central-1.

## Actions

1. Run the `env-up` workflow with `environment: stage`, `prod_size: true`, the hours and the reason. It opens the pull request that sets `size_window = "prod-size"` in `infra/live/stage/env.hcl` and keeps the stage workloads up through `deploy/envs/stage/keep-alive.yaml`. The plan shows the Aurora classes and readers, MemoryDB node type and shards, the node pool caps and analytics growing to the prod values. In that window, `config/environments/stage.yaml` still puts the payments and stateful pools on Spot.
2. After merge, apply stage through the GitHub Environment (approval required). MemoryDB at the new node type starts empty, and payment data comes from Aurora.
3. Run the test. The region switch is not tested on stage: it is a prod game day ([region-switch game day](../backup-dr/region-switch-game-day.md)).
4. Close the window: the hourly `env-up` run opens the pull request that returns stage to `size_window = "scheduled"` when the window expires. Apply it. MSK keeps its broker volume size, because volumes never shrink.
5. Record the window length in the issue of the test. The cost of the hours at the prod size shows on the FinOps dashboard (`observability/dashboards/finops/cost.json`).

## Escalation

If the window cannot be closed, for example because the apply fails, keep stage at the prod size and page the platform on-call. Stage then runs at the prod-size cost until the window is closed. Default chain: the primary acknowledges within 5 min, the secondary is paged at 5 min and the incident commander at 15 min (section 20.6).
