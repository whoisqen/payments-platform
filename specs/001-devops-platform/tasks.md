# Tasks: 001-devops-platform

Every item is one unit of work for one agent and one GitHub issue. The `id` becomes the commit trailer `Spec: specs/001-devops-platform#Tn`; `issue` is the GitHub issue in the milestone named by `milestone`. Done tasks were implemented before this specification and are delivered by the pull request `feat/infra-code-all` to `main` (#21); their state is in `progress/`.

## M1 Requirements baseline

```yaml
- id: T1
  title: Write the SRS overview: scope, actors, ID scheme, owner decisions D1-D8
  agent: docs-writer
  milestone: M1 Requirements baseline
  paths: ["docs/requirements/srs.md", "docs/requirements/README.md", "docs/glossary.md"]
  depends_on: []
  provides: srs overview
  requires: []
  acceptance: `tools/lint/srs-lint` exits 0; `grep -rP '[\x{0400}-\x{04FF}]' docs/requirements` prints nothing; every decision D1-D8 lists the passage it overrides
  issue: "#43"

- id: T2
  title: Write the numeric non-functional requirements (nfr.md)
  agent: docs-writer
  milestone: M1 Requirements baseline
  paths: ["docs/requirements/nfr.md"]
  depends_on: []
  provides: nfr ids
  requires: []
  acceptance: every value of AC4 of the spec is present in `nfr.md` (`grep` per value); `NFR-` IDs are defined only in `nfr.md`; `tools/lint/srs-lint` exits 0
  issue: "#44"

- id: T3
  title: Write the infrastructure requirements (AWS, network, cells, AZ, recovery region, Kubernetes, Helm)
  agent: docs-writer
  milestone: M1 Requirements baseline
  paths: ["docs/requirements/infrastructure.md"]
  depends_on: []
  provides: infrastructure ids
  requires: []
  acceptance: one requirement per control, each with one verification method and an implementation of at most 300 characters; `tools/lint/srs-lint` exits 0; withdrawn source passages are not carried over
  issue: "#45"

- id: T4
  title: Write the data and recovery requirements (data, backups, restore, resilience, warm-up)
  agent: docs-writer
  milestone: M1 Requirements baseline
  paths: ["docs/requirements/data-and-recovery.md"]
  depends_on: []
  provides: data ids
  requires: []
  acceptance: restore, retention, tier and lag numbers equal D2-D5 and D7; `tools/lint/srs-lint` exits 0
  issue: "#46"

- id: T5
  title: Write the security and access requirements (platform controls, zero trust, break-glass)
  agent: docs-writer
  milestone: M1 Requirements baseline
  paths: ["docs/requirements/security-and-access.md"]
  depends_on: []
  provides: security ids
  requires: []
  acceptance: no business behavior of the payment services appears; `tools/lint/srs-lint` exits 0
  issue: "#47"

- id: T6
  title: Write the delivery requirements (CI/CD, environments, promotion, hotfix, v* tags)
  agent: docs-writer
  milestone: M1 Requirements baseline
  paths: ["docs/requirements/delivery.md"]
  depends_on: []
  provides: delivery ids
  requires: []
  acceptance: promotion, hotfix and tag rules match `manifests/project.yaml` (`delivery`); `tools/lint/srs-lint` exits 0
  issue: "#48"

- id: T7
  title: Write the policy, as-code and cost requirements
  agent: docs-writer
  milestone: M1 Requirements baseline
  paths: ["docs/requirements/policy-and-cost.md"]
  depends_on: []
  provides: policy ids
  requires: []
  acceptance: every policy requirement names its enforcing tool (OPA, Kyverno, SCP, Config); `tools/lint/srs-lint` exits 0
  issue: "#49"

- id: T8
  title: Write the observability, scaling and testing requirements
  agent: docs-writer
  milestone: M1 Requirements baseline
  paths: ["docs/requirements/observability-and-testing.md"]
  depends_on: []
  provides: observability ids
  requires: []
  acceptance: alert thresholds equal `nfr.md`; `tools/lint/srs-lint` exits 0
  issue: "#50"

- id: T9
  title: Write the traceability table and confirm the SRS as the baseline
  agent: docs-writer
  milestone: M1 Requirements baseline
  paths: ["docs/requirements/traceability.md", "docs/requirements/*.md"]
  depends_on: ["T1", "T2", "T3", "T4", "T5", "T6", "T7", "T8", "T10"]
  provides: baseline
  requires: []
  acceptance: `tools/lint/srs-lint` exits 0 (no defined ID missing from the table, no cited ID undefined); the commit that sets the baseline passes `tools/lint/spec-gate`; an addendum before this commit is rejected by the gate
  issue: "#51"

- id: T10
  title: Write the ADR of the region model (data replicated, compute from Terraform, plan B)
  agent: docs-writer
  milestone: M1 Requirements baseline
  paths: ["docs/adr/0017-recovery-region-data-replication.md"]
  depends_on: ["T1"]
  provides: region adr
  requires: []
  acceptance: `ls docs/adr` shows the file; the front matter of the spec lists it under `adr`
  issue: "#52"
```

## M2 Repository as code

```yaml
- id: T11
  title: Write infra/github: organization, repository, security and Actions settings
  agent: terraform-engineer
  milestone: M2 Repository as code
  paths: ["infra/github/versions.tf", "infra/github/variables.tf", "infra/github/main.tf", "infra/github/backend.hcl.example", "infra/github/README.md", "infra/github/modules/organization/**", "infra/github/modules/repository/**"]
  depends_on: []
  provides: repository settings
  requires: []
  acceptance: `terraform fmt -check`, `validate`, `tflint` pass in `infra/github/`; `terraform test` in each module asserts the settings above with a mocked provider; `gitleaks detect` finds nothing
  issue: "#53"

- id: T12
  title: Write the rulesets (main, v* tags) and the environments (dev, stage, prod, cde-prod)
  agent: terraform-engineer
  milestone: M2 Repository as code
  paths: ["infra/github/modules/rulesets/**", "infra/github/modules/environments/**"]
  depends_on: ["T11"]
  provides: rulesets and environments
  requires: ["repository settings"]
  acceptance: `terraform test` in both modules passes; required check names equal the job names in `.github/workflows/ci.yml`
  issue: "#54"

- id: T13
  title: Generate CODEOWNERS from owners.yaml with the CDE ownership lines
  agent: terraform-engineer
  milestone: M2 Repository as code
  paths: ["infra/github/config/**", "infra/github/modules/codeowners/**"]
  depends_on: ["T11"]
  provides: codeowners
  requires: ["repository settings"]
  acceptance: a `terraform test` assertion checks one line per mapping; `CODEOWNERS` exists and matches the rendered output; `tools/lint/structure` passes
  issue: "#55"

- id: T14
  title: Write the repository files: PR template, Copilot instructions, SECURITY, Renovate, pre-commit, commitlint
  agent: ci-engineer
  milestone: M2 Repository as code
  paths: [".github/pull_request_template.md", ".github/copilot-instructions.md", "SECURITY.md", "renovate.json5", ".pre-commit-config.yaml", "commitlint.config.js"]
  depends_on: ["T12"]
  provides: repository files
  requires: ["rulesets and environments"]
  acceptance: `pre-commit validate-config`, `renovate-config-validator` and `commitlint --print-config` succeed; required check names equal those of T12
  issue: "#56"

- id: T15
  title: Verify the nightly GitHub drift workflow and fix its failing run
  agent: ci-engineer
  milestone: M2 Repository as code
  paths: [".github/workflows/github-drift.yml"]
  depends_on: ["T12"]
  provides: drift workflow
  requires: ["rulesets and environments"]
  acceptance: `actionlint` passes; one scheduled or manual run finishes green with `CHANGEME` values mocked or skipped as documented; a forced diff opens the alert issue
  issue: "#57"

- id: T16
  title: Add the commitlint and spec-gate parity test
  agent: ci-engineer
  milestone: M2 Repository as code
  paths: ["tools/ci/tests/commitlint-parity/**"]
  depends_on: ["T14"]
  provides: commit parity test
  requires: ["repository files"]
  acceptance: the test runs in `make test-python` and passes; a deliberately mismatched case makes it fail
  issue: "#58"
```

## M3 Cloud foundation

```yaml
- id: T17
  title: Write the state bootstrap, CI OIDC roles and AFT account requests
  agent: terraform-engineer
  milestone: M3 Cloud foundation
  paths: ["infra/bootstrap/**", "infra/aft-account-requests/**", "infra/modules/ci-oidc-roles/**"]
  depends_on: []
  provides: bootstrap
  requires: []
  acceptance: `terraform validate` and `terraform test` pass in each root and module; no account id outside variables
  issue: "#59"

- id: T18
  title: Write the network modules and the dev and stage stacks (VPC, TGW, egress VPC, Network Firewall)
  agent: terraform-engineer
  milestone: M3 Cloud foundation
  paths: ["infra/modules/vpc/**", "infra/modules/transit-gateway/**", "infra/modules/network-firewall/**", "infra/live/dev/eu-central-1/vpc/**", "infra/live/stage/eu-central-1/vpc/**", "infra/live/dev/eu-central-1/tgw/**", "infra/live/stage/eu-central-1/tgw/**", "infra/live/dev/eu-central-1/egress-vpc/**", "infra/live/stage/eu-central-1/egress-vpc/**", "infra/live/dev/eu-central-1/firewall/**", "infra/live/stage/eu-central-1/firewall/**"]
  depends_on: []
  provides: network
  requires: []
  acceptance: `terraform test` passes per module; `terragrunt validate` of each stack passes with mock outputs limited to init and validate
  issue: "#60"

- id: T19
  title: Write the edge, KMS, secrets-replica and ECR modules with their stacks
  agent: terraform-engineer
  milestone: M3 Cloud foundation
  paths: ["infra/modules/global-accelerator/**", "infra/modules/dns-certs/**", "infra/modules/kms/**", "infra/modules/kms-set/**", "infra/modules/secrets-replica/**", "infra/modules/ecr/**", "infra/live/dev/eu-central-1/edge-accelerator/**", "infra/live/stage/eu-central-1/edge-accelerator/**", "infra/live/dev/eu-central-1/edge-dns/**", "infra/live/stage/eu-central-1/edge-dns/**", "infra/live/dev/eu-central-1/kms/**", "infra/live/dev/us-east-1/kms/**", "infra/live/stage/eu-central-1/kms/**", "infra/live/stage/us-east-1/kms/**", "infra/live/dev/eu-central-1/secrets/**", "infra/live/stage/eu-central-1/secrets/**", "infra/live/dev/eu-central-1/ecr/**", "infra/live/dev/us-east-1/ecr/**", "infra/live/stage/eu-central-1/ecr/**", "infra/live/stage/us-east-1/ecr/**"]
  depends_on: []
  provides: edge and keys
  requires: []
  acceptance: `terraform test` passes per module (ecr: 4 tests); `terraform fmt -check -recursive infra` passes
  issue: "#61"
```

## M4 Data stores and recovery

```yaml
- id: T20
  title: Write the data-store modules and the cell stacks (Aurora global, DynamoDB global, MemoryDB, MSK, OpenSearch)
  agent: terraform-engineer
  milestone: M4 Data stores and recovery
  paths: ["infra/modules/aurora-global/**", "infra/modules/dynamodb-global/**", "infra/modules/memorydb/**", "infra/modules/msk/**", "infra/modules/opensearch/**", "infra/live/dev/eu-central-1/cell-*/**", "infra/live/dev/us-east-1/cell-*/**", "infra/live/stage/eu-central-1/cell-*/**", "infra/live/stage/us-east-1/cell-*/**", "infra/live/dev/eu-central-1/spare/**", "infra/live/dev/us-east-1/spare/**", "infra/live/stage/eu-central-1/spare/**", "infra/live/stage/us-east-1/spare/**", "infra/live/dev/eu-central-1/dynamodb/**", "infra/live/stage/eu-central-1/dynamodb/**", "infra/live/_envcommon/data/**"]
  depends_on: []
  provides: data stores
  requires: []
  acceptance: `terraform test` passes per module; recovery-region secondaries have no DB instance
  issue: "#62"

- id: T21
  title: Write the ClickHouse module and stack
  agent: terraform-engineer
  milestone: M4 Data stores and recovery
  paths: ["infra/modules/clickhouse/**"]
  depends_on: ["T20"]
  provides: clickhouse
  requires: ["data stores"]
  acceptance: `terraform fmt`, `validate`, `test` pass; RPO 15 min and RTO 4 h from `nfr.md` are asserted by a test
  issue: "#63"

- id: T22
  title: Write the backup modules and stacks (AWS Backup, vaults, S3 backup, event archive)
  agent: terraform-engineer
  milestone: M4 Data stores and recovery
  paths: ["infra/modules/backup/**", "infra/modules/s3-backup/**", "infra/live/dev/eu-central-1/backup/**", "infra/live/dev/us-east-1/backup/**", "infra/live/stage/eu-central-1/backup/**", "infra/live/stage/us-east-1/backup/**", "infra/live/dev/eu-central-1/s3-backup/**", "infra/live/dev/us-east-1/s3-backup/**", "infra/live/stage/eu-central-1/s3-backup/**", "infra/live/stage/us-east-1/s3-backup/**", "infra/live/dev/eu-central-1/s3-event-archive/**", "infra/live/dev/us-east-1/s3-event-archive/**", "infra/live/stage/eu-central-1/s3-event-archive/**", "infra/live/stage/us-east-1/s3-event-archive/**"]
  depends_on: []
  provides: backups
  requires: []
  acceptance: `terraform test` passes per module; a stateful resource without a backup plan is rejected by the OPA test (see T31)
  issue: "#64"

- id: T23
  title: Write the us-east-2 recovery stacks and the restore automation
  agent: terraform-engineer
  milestone: M4 Data stores and recovery
  paths: ["infra/live/dev/us-east-2/**", "infra/live/stage/us-east-2/**"]
  depends_on: ["T20", "T22"]
  provides: recovery region
  requires: ["data stores", "backups"]
  acceptance: `terragrunt validate` passes for every us-east-2 stack; `backup_restore_duration_seconds` alert at 80% of 30 minutes exists in `observability/alerts` (cross-check with T33)
  issue: "#65"
```

## M5 Kubernetes platform and delivery

```yaml
- id: T24
  title: Write the EKS, Karpenter and workload-IAM modules with the dev and stage settings
  agent: terraform-engineer
  milestone: M5 Kubernetes platform and delivery
  paths: ["infra/modules/eks/**", "infra/modules/karpenter/**", "infra/modules/iam-workloads/**", "infra/live/_envcommon/compute/**", "infra/live/dev/env.hcl", "infra/live/stage/env.hcl"]
  depends_on: []
  provides: eks
  requires: []
  acceptance: `terraform test` passes per module; `ci-prod` pool is on-demand with taint `workload=ci-prod:NoSchedule`
  issue: "#66"

- id: T25
  title: Isolate the locker data access: pod security groups as the only clients
  agent: terraform-engineer
  milestone: M5 Kubernetes platform and delivery
  paths: ["infra/modules/data-access/**", "infra/live/dev/eu-central-1/locker/**", "infra/live/dev/us-east-1/locker/**", "infra/live/stage/eu-central-1/locker/**", "infra/live/stage/us-east-1/locker/**"]
  depends_on: ["T24"]
  provides: locker isolation
  requires: ["eks"]
  acceptance: `terraform test` asserts no node SG in the client list; `REPLACE_LOCKER_POD_SG_ID` is the only placeholder left (T40)
  issue: "#67"

- id: T26
  title: Write the Helm charts and the dev and stage values (library, services, cell and edge umbrellas, locker)
  agent: k8s-engineer
  milestone: M5 Kubernetes platform and delivery
  paths: ["deploy/charts/**", "deploy/envs/dev/values.yaml", "deploy/envs/stage/values.yaml", "deploy/envs/dev/eu-central-1/**", "deploy/envs/stage/eu-central-1/**"]
  depends_on: []
  provides: charts
  requires: []
  acceptance: `make lint-helm` and `make test-helm` pass (CI job `helm` green); images are referenced by digest only
  issue: "#68"

- id: T27
  title: Write the Argo CD AppProjects, ApplicationSets and platform add-ons
  agent: k8s-engineer
  milestone: M5 Kubernetes platform and delivery
  paths: ["deploy/argocd/**", "deploy/platform/istio/**", "deploy/platform/cert-manager/**", "deploy/platform/karpenter/**", "deploy/platform/kube-prometheus/**", "deploy/platform/kyverno/**", "deploy/platform/otel-collector/**"]
  depends_on: []
  provides: gitops
  requires: []
  acceptance: `kubeconform` passes on the rendered manifests; no add-on pinned to a floating tag
  issue: "#69"

- id: T28
  title: Write the CI/CD workflows: ci, images, promote, hotfix, tag, nightly, CodeQL
  agent: ci-engineer
  milestone: M5 Kubernetes platform and delivery
  paths: [".github/workflows/ci.yml", ".github/workflows/images.yml", ".github/workflows/promote.yml", ".github/workflows/hotfix.yml", ".github/workflows/tag.yml", ".github/workflows/nightly.yml", ".github/workflows/codeql.yml", "tools/ci/changed_images.py", "tools/ci/digest_compare.py", "tools/ci/dockerfile_check.py", "tools/ci/images_yaml.py", "tools/ci/next_version.py", "tools/ci/placeholder_report.py", "tools/ci/image-paths.yaml", "tools/ci/tests/test_*.py", "docker/**", "Makefile", "mise.toml", "scripts/**"]
  depends_on: []
  provides: pipelines
  requires: []
  acceptance: `ci-gate` is green on PR #21; CodeQL reports no open alert from this PR; `make lint test` passes locally for the changed areas
  issue: "#70"

- id: T29
  title: Write the ARC runner pool chart: controller values, ci-prod, ci-stage and ci-pr scale sets
  agent: k8s-engineer
  milestone: M5 Kubernetes platform and delivery
  paths: ["deploy/platform/arc/**"]
  depends_on: ["T27"]
  provides: arc chart
  requires: ["gitops"]
  acceptance: `helm lint` and `helm unittest` pass; ci-pr runners have no route to cell or CDE namespaces (NetworkPolicy test)
  issue: "#71"

- id: T30
  title: Deploy the ARC pool to shared-services: Karpenter unit, GitHub App keys, runner digest
  agent: terraform-engineer
  milestone: M5 Kubernetes platform and delivery
  paths: ["infra/live/shared-services/**"]
  depends_on: ["T24", "T29"]
  provides: arc deployment
  requires: ["eks", "arc chart"]
  acceptance: `terragrunt validate` passes; ARC controller and scale sets sync healthy in Argo CD (owner step after the first deployment); a test job in ci-pr cannot reach cell or CDE namespaces
  issue: "#72"
```

## M6 Security, policy and observability

```yaml
- id: T31
  title: Write the policy as code: SCP, OPA, Kyverno, AWS Config, Semgrep, tagging
  agent: policy-engineer
  milestone: M6 Security, policy and observability
  paths: ["policy/opa/**", "policy/kyverno/**", "policy/scp/**", "policy/config/**", "policy/semgrep/**", "policy/tagging/**", "policy/exceptions.yaml", "policy/README.md"]
  depends_on: []
  provides: policies
  requires: []
  acceptance: `opa test policy/opa` and `kyverno test policy/kyverno` pass; `opa fmt --fail -l` is clean
  issue: "#73"

- id: T32
  title: Write the Vault and External Secrets deployment with Raft snapshots and break-glass access
  agent: k8s-engineer
  milestone: M6 Security, policy and observability
  paths: ["deploy/platform/vault/**", "deploy/platform/external-secrets/**"]
  depends_on: []
  provides: secrets platform
  requires: []
  acceptance: `helm lint` and `kubeconform` pass; no secret value in any file (`gitleaks detect`)
  issue: "#74"

- id: T33
  title: Write the observability: SLO rules, alerts, dashboards, exporters, OTel, runbooks
  agent: observability-engineer
  milestone: M6 Security, policy and observability
  paths: ["observability/alertmanager/**", "observability/alerts/**", "observability/dashboards/**", "observability/exporters/**", "observability/lib/**", "observability/otel/**", "observability/slo/**", "observability/standards/**", "observability/tests/**", "observability/README.md", "observability/coverage/alert_coverage.py", "observability/coverage/metrics-catalog.json", "observability/coverage/targets.yaml", "observability/coverage/catalog/**", "observability/coverage/tests/**", "docs/runbooks/**"]
  depends_on: []
  provides: observability
  requires: []
  acceptance: `python3 observability/tests/run.py` passes (promtool check and test); every alert has a runbook file
  issue: "#75"

- id: T34
  title: Limit the OIDC trust of the CI roles to main and release/*
  agent: terraform-engineer
  milestone: M6 Security, policy and observability
  paths: ["infra/modules/ci-oidc-roles/**"]
  depends_on: ["T17"]
  provides: oidc trust
  requires: ["bootstrap"]
  acceptance: a `terraform test` asserts the `sub` list; no wildcard `sub` remains
  issue: "#76"

- id: T35
  title: Limit the CI apply-role exception in the SCP to the exact role ARN
  agent: policy-engineer
  milestone: M6 Security, policy and observability
  paths: ["policy/scp/security-baseline.json"]
  depends_on: ["T31"]
  provides: scp exact arn
  requires: ["policies"]
  acceptance: `opa test` for the SCP passes with a negative case for another account; JSON validates against the SCP schema
  issue: "#77"
```

## M7 Verification and release readiness

```yaml
- id: T36
  title: Write the k6 load scenarios, chaos experiments and capacity model
  agent: perf-engineer
  milestone: M7 Verification and release readiness
  paths: ["tests/load/**", "tests/chaos/**", "docs/capacity/**", "docs/chaos/**"]
  depends_on: []
  provides: load and chaos
  requires: []
  acceptance: k6 and Python unit tests pass; each experiment has hypothesis, abort condition and expected alert
  issue: "#78"

- id: T37
  title: Write the smoke, e2e and contract tests
  agent: test-engineer
  milestone: M7 Verification and release readiness
  paths: ["tests/smoke/**", "tests/e2e/**", "tests/contracts/**", "tests/README.md"]
  depends_on: []
  provides: functional tests
  requires: []
  acceptance: all tests run offline with mocks in CI; `tests/README.md` lists how to run each suite
  issue: "#79"

- id: T38
  title: Pin or gate automated prod sync in Argo CD and verify the AppProject whitelist
  agent: k8s-engineer
  milestone: M7 Verification and release readiness
  paths: ["deploy/argocd/templates/applicationset-cells.yaml", "deploy/argocd/templates/appprojects.yaml"]
  depends_on: ["T27"]
  provides: argocd prod gate
  requires: ["gitops"]
  acceptance: `kubeconform` passes; no prod Application has `targetRevision: main` with automated sync
  issue: "#80"

- id: T39
  title: Update the threat model for the ci-pr network perimeter
  agent: docs-writer
  milestone: M7 Verification and release readiness
  paths: ["docs/security/**"]
  depends_on: ["T29"]
  provides: threat model
  requires: ["arc chart"]
  acceptance: each new trust boundary has a threat, a mitigation and an owner; `/glossary-check` has no warning
  issue: "#81"

- id: T40
  title: Wire the locker pod security group id and clear the REPLACE_* placeholders in deploy values
  agent: k8s-engineer
  milestone: M7 Verification and release readiness
  paths: ["deploy/envs/dev/values.yaml", "deploy/envs/stage/values.yaml"]
  depends_on: ["T26"]
  provides: no deploy placeholders
  requires: ["charts"]
  acceptance: the report lists no `REPLACE_*` for the environment about to be applied, or each remaining one has an owner in the ticket; locker pod security group id is set in dev and stage values
  issue: "#82"

- id: T41
  title: Write the SRS addendum for the two-region model and the FinOps sizes
  agent: docs-writer
  milestone: M7 Verification and release readiness
  paths: ["docs/requirements/addenda/001-two-regions-finops.md"]
  depends_on: ["T9"]
  provides: two-region addendum
  requires: ["baseline"]
  acceptance: `tools/lint/srs-lint` exits 0 with the addendum; every changed or withdrawn requirement ID names its reason
  issue: "#199"

- id: T42
  title: Write the SRS addendum for the central OpenSearch logs
  agent: docs-writer
  milestone: M7 Verification and release readiness
  paths: ["docs/requirements/addenda/002-central-logs.md"]
  depends_on: ["T41"]
  provides: central logs addendum
  requires: ["two-region addendum"]
  acceptance: `tools/lint/srs-lint` exits 0 with the addendum; FR-INF-24 and FR-OBS-1 name the central OpenSearch
  issue: "#205"
```
