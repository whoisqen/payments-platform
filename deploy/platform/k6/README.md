# k6 load tests on stage

- `values-k6-operator.yaml` and `envs/<env>/<region>.operator.yaml`: the upstream `grafana/k6-operator` chart (pinned in `deploy/argocd/templates/addons/loadgen/k6.yaml`), namespace `k6-operator`.
- `runs/`: chart in namespace `loadgen` with one CronJob per scenario of section 8; each creates a TestRun named `<scenario>-<UTC time>`, which is also its `testid` tag in VictoriaMetrics. `envs/<env>/<region>.yaml` is its layer.
- Clusters: only those labelled `payments-platform/environment=stage` and `payments-platform/loadgen=enabled`; the chart fails the render for any other environment or a prod or CDE target.
- Scripts: `runs/scripts/load` and `runs/scripts/chaos` are symlinks to `tests/load` and `tests/chaos`; the chart packs the `.js` files into the `k6-scripts` ConfigMap and a projected volume restores the paths, so relative imports work.
- Schedule (UTC): load (daily-peak) 01:00 daily, stress Wed 03:00, soak Sat 02:00, spike on the 1st 23:00; breakpoint, hot-merchant and shedding are on demand: `kubectl -n loadgen create job --from=cronjob/k6-<name> k6-<name>-manual`.
- Guard: the CronJob refuses to start unless the environment is stage, `target.freeze` is false and the target host is not prod or CDE; the scripts check the same at init.
- Secret: Vault KV `secret/loadgen/test-merchants` with `merchant_api_key`, `test_payment_token`, `merchant_id`, `webhook_secret`, `hot_merchant_id`, `other_merchant_ids` (test merchants on the dummy connector, never card data).
- Nodes: Karpenter NodePool `loadgen` (label and taint `workload=loadgen`, On-Demand); runner pods carry `karpenter.sh/do-not-disrupt`.
