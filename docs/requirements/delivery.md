---
status: baseline
---

# Delivery requirements

CI/CD, environments, promotion, the hotfix pipeline, `v*` tags, zero manual actions and infrastructure tests. Branch and environment rules follow `manifests/project.yaml` (`delivery`).

## Branches and pull requests

| ID | Requirement | Verification | Implementation | Source |
|---|---|---|---|---|
| FR-DEL-1 | `main` shall be the only long-lived branch; changes shall arrive by squash-merged pull requests from short-lived `<type>/<n>-<slug>` branches, and environments shall be directories, never branches. | test | Ruleset of `infra/github/modules/rulesets` (no force push, linear history); `deploy/envs/<env>/`, `infra/live/<env>/`; `terraform test` in `infra/github`. | Section 27.5 |
| FR-DEL-2 | A pull request to `main` shall need 2 approvals with one from CODEOWNERS, stale approvals dismissed, last-push approval, resolved threads and the required checks passing. | test | `required_approving_review_count = var.main_approvals` (default 2), `require_last_push_approval`, `required_status_checks` in `infra/github/modules/rulesets`; `CODEOWNERS` from `infra/github/config/owners.yaml`. | Section 10 |
| FR-DEL-3 | Every commit subject shall follow Conventional Commits and every non-exempt commit shall cite an approved or in-progress specification task. | test | Jobs `commitlint` and `spec-gate` of `.github/workflows/ci.yml`; `tools/lint/spec-gate` as the `commit-msg` hook; parity tests in `tools/lint/tests`. | Section 27.6 |
| FR-DEL-4 | The pull request gate shall run only the checks of the changed areas and pass through one job `ci-gate` that waits for all of them. | test | Jobs `changes` and `ci-gate` of `.github/workflows/ci.yml`; `actionlint`. | Section 9 (pipeline) |

## Build and promotion

| ID | Requirement | Verification | Implementation | Source |
|---|---|---|---|---|
| FR-DEL-5 | An image shall be built once per merge to `main` or `release/*`, pushed by digest, signed with cosign and attested with an SBOM and build provenance. | test | `.github/workflows/images.yml` (rootless BuildKit, syft CycloneDX, `cosign attest`, `attest-build-provenance`, `cosign sign`); OPA `policy/opa/docker/*`. | Section 9 (images), section 20.5 |
| FR-DEL-6 | Promotion shall be a pull request that changes `deploy/envs/<env>/images.yaml`: dev after a successful image build, stage after a green dev smoke run, prod after a green stage smoke run. | test | `.github/workflows/promote.yml` (`workflow_run`, `repository_dispatch` `smoke-green-dev`, `smoke-green-stage`); `tests/e2e/test_promotion.py`. | Section 9 (environments), section 27.6 |
| FR-DEL-7 | Stage and prod shall receive only digests that already ran in the previous environment. | test | Job `promotion` of `.github/workflows/ci.yml` runs `tools/ci/images_yaml.py verify` against the source environment and its history. | Section 9 |
| FR-DEL-8 | A prod promotion pull request shall pass the approvals of the `main` ruleset, and the GitHub Environments shall require SRE reviewers for prod and SRE and security reviewers for cde-prod. | test | Ruleset of `infra/github/modules/rulesets`; reviewers per environment in `infra/github/modules/environments` (dev and stage none, prod sre, cde-prod sre and security); `terraform test` in `infra/github`. | Section 9, section 10 |
| FR-DEL-9 | Prod Argo CD Applications shall be pinned to one revision and have no automated sync, and cells shall be synced one at a time. | test | `deploy/argocd/templates/applicationset-gated.yaml` (no `automated` sync policy); `deploy/argocd/tests`. | Section 4 (GitOps), ADR-010 |
| FR-DEL-10 | A new version of router and locker shall roll out per cell as an Argo Rollouts canary with Istio traffic weights and an AnalysisRun on errors and p99. | test | `rollout` templates of `platform-common` (`setWeight` steps); `deploy/charts/router/templates/istio/{canary,analysistemplate}.yaml`; chart `tests/`. | Section 4 (deployment strategies), ADR-013b |
| FR-DEL-11 | After every sync in dev and stage a PostSync smoke Job shall run a synthetic payment through the dummy connector, and its green result shall trigger the next promotion. | test | `deploy/platform/smoke/job` and `notifications`; `tests/smoke/test_synthetic_payment.py`, `test_service_health.py`; alert `SyntheticPaymentFailing`. | Section 8 (smoke tests) |
| FR-DEL-12 | A promotion run shall never be cancelled, and one run per environment shall be active at a time. | inspection | `concurrency` `promote-<env>` with `cancel-in-progress: false` in `.github/workflows/promote.yml`. | Section 9 |
| FR-DEL-13 | Promoted images shall get an `<env>-<digest>` tag that the registry retention keeps for rollback. | test | `.github/workflows/tag-deployed.yml` with `tools/ci/deployed_tags.py`; ECR lifecycle of `infra/modules/ecr` (last 50 tagged kept). | Section 9 (version lifecycle) |

## Hotfix and versions

| ID | Requirement | Verification | Implementation | Source |
|---|---|---|---|---|
| FR-DEL-14 | A hotfix shall be built from `release/<tag>` created from the version running in prod, promoted straight to the cells named in the pull request, and pass the full CI afterwards. | test | `.github/workflows/hotfix.yml` (`release-branch`, `build`, `full-ci`); `hotfix` label and `Cells:` line read by `promote.yml`. | Section 9, section 27.5 |
| FR-DEL-15 | A hotfix shall contain no migration, and planned promotions shall wait while a hotfix has failed its full CI. | test | Job `hotfix-guard` of `.github/workflows/ci.yml`; `hold` on open `hotfix-ci-failed` issues in `promote.yml`; job `alert-full-ci` of `hotfix.yml`. | Section 9 |
| FR-DEL-16 | A merged hotfix shall be backported to `main` by an automatic pull request. | test | Job `backport` of `.github/workflows/hotfix.yml`. | Section 27.5 |
| FR-DEL-17 | `v*` tags (SemVer `vX.Y.Z`: breaking change major, `feat` minor, `fix` patch) shall be created only by the tagging workflow after a prod rollout in all cells, for a commit on `main` or `release/*`. | test | `.github/workflows/tag.yml` (`prod-rollout-complete`); `tools/ci/next_version.py` with tests in `tools/ci/tests`. | D1 |
| FR-DEL-18 | Creation of `v*` tags shall be allowed only to the tagging workflow, and deletion or move shall be denied to everyone. | test | Tag ruleset on `refs/tags/v*` in `infra/github/modules/rulesets`; `terraform test` in `infra/github`. | D1 |
| FR-DEL-19 | A tag shall build nothing and attach a changelog, SBOM and provenance; the image digest shall stay the version identifier. | test | Jobs `evidence` and `publish` of `.github/workflows/tag.yml`. | D1 |

## Infrastructure as code

| ID | Requirement | Verification | Implementation | Source |
|---|---|---|---|---|
| FR-DEL-20 | Every Terraform module shall pass `fmt`, `validate`, `tflint` and `terraform test` with a mocked provider, and every Terragrunt stack shall validate. | test | `make lint-terraform test-terraform` in the `terraform` job of `.github/workflows/ci.yml`; `tests/` of each module under `infra/modules/`. | Section 18 (infrastructure autotests) |
| FR-DEL-21 | Charts shall pass `helm lint --strict`, kubeconform and `helm unittest`; policies `opa test` and `kyverno test`; alerts `promtool test rules`. | test | `make lint-helm test-helm test-policy`; `observability/tests/run.py`; jobs `helm`, `policy` of `.github/workflows/ci.yml`. | Section 18, section 15 |
| FR-DEL-22 | Terraform shall be applied only by per-component apply roles whose OIDC trust admits `main` and `release/*`, and pull requests shall get only the read-only plan role. | test | Roles `pay-<env>-glob-tf-plan` and `pay-<env>-glob-tf-apply-<component>` of `infra/modules/ci-oidc-roles` (1 h session, own state prefix); negative cases in its `tests/`. | Section 9 (IaC), section 23.3 |
| FR-DEL-23 | Drift between code and AWS or GitHub shall be detected every night and open an issue. | test | Jobs `drift`, `alert-drift`, `github-drift` of `.github/workflows/nightly.yml` (plan without apply). | Section 9, section 10 |
| FR-DEL-24 | No operation shall need a manual step outside a reviewed pull request, a recorded approval, the per-cell Argo CD sync of a pinned prod revision, or a human confirmation recorded by an automated tool. | inspection | Promotion by `promote.yml`, tags by `tag.yml`, restore by `infra/modules/restore-automation`, failover by `infra/modules/dr-failover`, cell moves by `scripts/cells/migrate-merchant.py`. | Section 14 (zero manual actions) |
| FR-DEL-25 | Placeholders shall be the only unknown values and shall be listed by one report. | test | `tools/ci/placeholder_report.py` with tests in `tools/ci/tests`. | Section 14 |
