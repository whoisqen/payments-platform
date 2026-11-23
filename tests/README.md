# tests

The platform's own tests: `smoke/`, `load/`, `chaos/`, `e2e/`, `nodes/`, `alerts/`, `contracts/`. Upstream tests live in `vendor/hyperswitch-e2e/`.

Offline suites need only Python 3 and PyYAML; no network, AWS, card data or secrets.

- `smoke/`: a synthetic payment (create, capture, read, refund) through a fake edge and test PSP for every cell routed in `deploy/envs/<env>/<region>/edge/values.yaml`, plus probe and port checks of every service chart. Budget 90 seconds. Run `python3 -m unittest discover -s tests/smoke`.
- `e2e/`: promotion dev to stage by image digest through `tools/ci/images_yaml.py` and `tools/ci/digest_compare.py` on temporary files. Run `python3 -m unittest discover -s tests/e2e`.
- `contracts/`: environment values merged over chart defaults against `deploy/charts/*/values.schema.json` (a minimal in-repo validator), and alert `failure_mode` and `runbook_url` against `observability/coverage` and `docs/runbooks`. Run `python3 -m unittest discover -s tests/contracts`.
- All three at once: `python3 -m unittest discover -s tests`.
- `chaos/` and `load/` have their own READMEs; `nodes/` and `alerts/` (chainsaw, promtool) are not written yet.
