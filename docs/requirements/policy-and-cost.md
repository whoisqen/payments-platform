---
status: baseline
---

# Policy, as-code and cost requirements

Repository and policy as code, the other as-code layers, tagging and FinOps. Every policy requirement names its enforcing tool. Cost numbers are in `nfr.md` (`NFR-COST-*`).

## Repository as code

| ID | Requirement | Verification | Implementation | Source |
|---|---|---|---|---|
| FR-POL-1 | Organization, repository settings, rulesets, environments and CODEOWNERS shall be managed by Terraform, with drift detected every night. | test | `infra/github/` with modules `organization`, `repository`, `rulesets`, `environments`, `codeowners` and their `tests/`; job `github-drift` of `.github/workflows/nightly.yml`. | Section 10 (repository as code) |
| FR-POL-2 | The repository shall allow squash merge only, delete merged branches, keep `GITHUB_TOKEN` read-only and allow only SHA-pinned actions from an allowlist. | test | `infra/github/modules/repository` and `organization`; `terraform test` in `infra/github`. | Section 10 |
| FR-POL-3 | CODEOWNERS shall be generated from one owners file, and CDE paths shall need approval from their owning teams. | test | `infra/github/config/owners.yaml` rendered by `infra/github/modules/codeowners`; CDE paths in `policy/cde-paths.yaml`; assertion in `infra/github/modules/codeowners/tests`. | Section 10 |
| FR-POL-4 | Dependency updates shall be proposed by Renovate with digests pinned. | inspection | `renovate.json5`, validated by `renovate-config-validator`. | Section 10, section 20.5 |

## Policy as code

| ID | Requirement | Verification | Implementation | Source |
|---|---|---|---|---|
| FR-POL-5 | OPA shall deny a Terraform plan that creates a stateful resource (Aurora, RDS, DynamoDB, MemoryDB, EBS, EFS, S3, OpenSearch) without a backup plan or point-in-time recovery. | test | `policy/opa/terraform/no-stateful-without-backup` with its test file; `make test-policy`. | D2, section 10 |
| FR-POL-6 | OPA shall deny a stateful resource without a valid `backup-tier` tag. | test | `policy/opa/terraform/backup-tier-required` with its test file. | D2, section 19 |
| FR-POL-7 | The only way around a policy shall be an entry in `policy/exceptions.yaml` naming rule, resource, owner, reason and expiry; an expired entry shall fail CI. | test | `policy/opa/lib/exceptions` with `exceptions-test.rego`; `policy/exceptions.yaml`. | D2, section 19 |
| FR-POL-8 | Kyverno shall reject a migration Job that does not start with the pre-migration snapshot init container or keeps the snapshot less than 35 days. | test | `policy/kyverno/require-migration-snapshot` with `kyverno-test.yaml`. | D3 |
| FR-POL-9 | Kyverno shall require probes and a PodDisruptionBudget for every workload, and OPA shall check the same in rendered charts. | test | `policy/kyverno/require-probes`, `policy/kyverno/require-pdb`; `policy/opa/kubernetes/require-pdb`. | Section 10, section 4 |
| FR-POL-10 | An SCP shall deny every API call outside eu-central-1, us-east-1 and us-east-2, except global services. | test | `policy/scp/region-allow-list.json` (`DenyOutsideAllowedRegions`), attached by `infra/modules/org-policies`; `policy/scp/tests/test_scp.py`. | D7, section 3 |
| FR-POL-11 | An SCP shall deny DynamoDB writes in us-east-1 and us-east-2 except by the replication service, and the promotion shall detach it for the promoted region. | test | `policy/scp/deny-dynamodb-writes-recovery-regions.json`; `scripts/dr/failover.py`; `policy/scp/tests/test_scp.py`. | D7 |
| FR-POL-12 | AWS Config shall evaluate the PCI DSS v4 conformance pack and the custom rules in every account and region. | test | `policy/config/pci-dss-pack/pci-dss-v4.yaml`, `policy/config/custom-rules/custom-rules.yaml` with their `-test.rego` files; `infra/modules/org-config`. | Section 20.4 |
| FR-POL-13 | OPA shall require Object Lock on every backup bucket and a customer managed KMS key on every encrypted resource. | test | `policy/opa/terraform/s3-object-lock-required`, `policy/opa/terraform/kms-cmk-required` with their tests. | D5, section 6 |
| FR-POL-14 | Backup policies of the organization shall be attached from the repository as they are written. | test | `policy/scp/backup-policies/backup-tiers.json` attached by `infra/modules/org-policies` (a document without a target fails the plan). | Section 19 |

## Other as-code layers

| ID | Requirement | Verification | Implementation | Source |
|---|---|---|---|---|
| FR-POL-15 | Kafka topics shall be created only from code; topic auto-creation and unauthenticated access shall be off. | test | `infra/modules/msk` (`auto.create.topics.enable=false`, IAM auth only) and `tests/msk.tftest.hcl`. | Section 20.2 |
| FR-POL-16 | The resilience policy of every dependency (timeout, attempts, backoff, budget) shall be one validated file. | test | `policy/resilience/policy.yaml` with `schema.json`, `validate.py` and `tests/test_validate.py`. | Section 24.6 |
| FR-POL-17 | The developer toolchain shall be pinned in one file and installed by one command. | inspection | `mise.toml`; `make bootstrap` (tools and git hooks). | Section 20.10 |

## Tagging

| ID | Requirement | Verification | Implementation | Source |
|---|---|---|---|---|
| FR-POL-18 | Every AWS resource shall carry the tags `environment`, `team`, `owner`, `cost-center`, `cell`, `component`, `pci-scope`, `data-class`, `backup-tier`, `managed-by` and `repo` with values from one schema. | test | `policy/tagging/schema.yaml`; OPA `policy/opa/terraform/required-tags`; `default_tags` in `infra/live/terragrunt.hcl`. | Section 22.1, section 22.2 |
| FR-POL-19 | Organization tag policies shall be generated from the same schema and kept in sync with it. | test | `policy/scp/tag-policies/required-tags.json`; `policy/tagging/tests/tag-policy-sync-test.rego`. | Section 22.3, section 22.6 |
| FR-POL-20 | Protected tags shall be editable only by automation. | test | SCP `policy/scp/deny-tag-edit.json` (`DenyEditingProtectedTagsExceptAutomation`); `policy/scp/tests/test_scp.py`. | Section 22.3 |
| FR-POL-21 | Resources shall be grouped by environment, cell and component through tags and the `pay-<env>-<region-short>-<component>` naming. | test | `policy/tagging/tests/org-trees-values-test.rego`; naming in module variables. | Section 22.4 |

## Cost

| ID | Requirement | Verification | Implementation | Source |
|---|---|---|---|---|
| FR-COST-1 | Cost per 1,000 payments, month-to-date spend, budget use and daily spend by component shall be visible on one dashboard, grouped by the `cost-center` and `component` tags. | inspection | `observability/dashboards/finops/cost.json` (`finops_cost_usd_per_day`, `finops_budget_usd_month`). | Section 12 (visibility), section 22.5 |
| FR-COST-2 | Node pools shall use Spot only where `spot_pools` allows it, never for the `cde` pool or in prod, and Karpenter shall remove empty nodes. | test | `spot_pools` in `config/environments/{dev,stage}.yaml`; consolidation `WhenEmpty` in `infra/modules/karpenter`; panel `finops: spot interruptions per hour`. | Section 12 (price type) |
| FR-COST-3 | CI runners shall be Spot instances that keep `warm_size` instances only during working hours. | test | Scheduled actions of `infra/modules/ci-runners` and `tests/ci-runners.tftest.hcl`. | Section 12 (schedules) |
| FR-COST-4 | The us-east-1 standby shall run capped node pools and one Aurora reader per cell, and dev shall run no standby. | inspection | `standby.node_pool_cpu_limits` and `reader_count` in `config/environments/prod.yaml`; `standby.enabled: false` in `config/environments/dev.yaml`. | ADR-0017 |
| FR-COST-5 | Object backups shall be tiered by lifecycle rules (`NFR-REC-15`) and ECR shall expire untagged images after 14 days. | test | `infra/modules/s3-backup` lifecycle; `infra/modules/ecr` lifecycle policy; module `tests/`. | D5, section 12 |
| FR-COST-6 | AI usage shall have a monthly budget with alerts at 80% and 100% and a token-volume alarm. | test | `aws_budgets_budget.bedrock` and the input-token alarm in `infra/modules/bedrock-access`; its `tests/`. | Section 12, section 23.5 |
