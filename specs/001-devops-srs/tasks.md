# Tasks: 001-devops-srs

Every item is one unit of work for one agent. The `id` becomes the commit trailer `Spec: specs/001-devops-srs#Tn`; `issue` is a GitHub issue in the specification's milestone, created after the approval (`none` until then). T1 to T8 write disjoint files and run in parallel, T11 needs the owner decisions of T1, T9 needs all IDs, T10 changes the status line of the finished files and is the last commit.

```yaml
- id: T1
  title: Write the introduction, scope, source pin, owner decisions and open issues
  agent: docs-writer
  paths: ["docs/requirements/srs.md", "docs/glossary.md", "docs/requirements/README.md"]
  depends_on: []
  provides: requirements overview
  requires: []
  acceptance: AC6, AC9 and AC11 hold; srs.md has scope, actors, assumptions, the ID scheme and area codes, the pinned source, the list of terms used in another sense, D1 to D8 with the source passage each overrides, the list of withdrawn source passages, the accepted idempotency risk and the VPC CIDRs of the recovery regions as decisions, with no open issue left in srs.md except those the writers find; no requirement rows; the glossary terms are added
  issue: "#2"

- id: T2
  title: Write the numeric non-functional requirements
  agent: docs-writer
  paths: ["docs/requirements/nfr.md"]
  depends_on: []
  provides: numeric targets
  requires: []
  acceptance: AC2, AC3, AC4, AC6, AC7 and AC9 hold; every value listed in AC4 is present, including the owner numbers of D2 to D8
  issue: "#3"

- id: T3
  title: Write the infrastructure requirements (AWS, network, cells, AZ availability, recovery region on demand, Kubernetes, Helm, node security)
  agent: docs-writer
  paths: ["docs/requirements/infrastructure.md"]
  depends_on: []
  provides: infrastructure requirements
  requires: []
  acceptance: AC2, AC3, AC6, AC7, AC9 and AC10 hold; covers sections 2 (platform parts), 3, 4 (clusters), 17, 20.8, 21.1 and 26 with one requirement per control; D6 (Frankfurt as the only writing region, three AZs, writer of each cell in a different AZ, semi-automatic switch with fencing, no compute in the recovery region); the infrastructure side of D7 (non-compute prepared in us-east-1 and us-east-2 including egress Elastic IPs registered with PSPs and the Global Accelerator endpoint group, compute created from Terraform at the switch, the RTO budget, plan B with several instance families, the ordered Aurora class list and the switch to us-east-2 after 10 minutes without capacity); every tool the switch needs runs outside eu-central-1 or is created inside the RTO budget (runbook, Terraform state, images, runners, Vault, ArgoCD, monitoring from three independent points); NFR IDs cited, not defined; withdrawn source passages not carried over
  issue: "#4"

- id: T4
  title: Write the data and recovery requirements (data, backups, restore, resilience, warm-up)
  agent: docs-writer
  paths: ["docs/requirements/data-and-recovery.md"]
  depends_on: []
  provides: data and recovery requirements
  requires: []
  acceptance: AC2, AC3, AC6, AC7 and AC9 hold; covers sections 5, 19, 24, 21.2, 21.3, the backup tiers of 21.5 and from section 2 the write path through Redis streams and drainer, PSP interaction timings, patterns and CAP/PACELC; D2 to D5 (the 30-minute target only for logical-error restores in Frankfurt); the data side of D7 (Aurora Global Database secondaries without instances in us-east-1 and us-east-2 with the 5 s alert and 10 s budget, DynamoDB Global Tables with replicas in both, written only from Frankfurt, MemoryDB rebuilt from Aurora, MSK rebuilt from the S3 archive, S3 replication with Replication Time Control, hourly snapshot copies and ECR replication to both regions; plan B: promotion in exactly one region under a lock, the other region follows the new writer); D8 (75% of the priority hot keys, wait at most 5 minutes, then traffic and a non-paging alert); each rule has a metric or test; infrastructure and policies are cited from T3 and T7; withdrawn source passages not carried over
  issue: "#5"

- id: T5
  title: Write the security and access requirements (platform controls, access, zero trust, break-glass)
  agent: docs-writer
  paths: ["docs/requirements/security-and-access.md"]
  depends_on: []
  provides: security and access requirements
  requires: []
  acceptance: AC2, AC3, AC6, AC7 and AC9 hold; covers sections 6 (platform controls only), 16, 20.1, 20.3, 20.4, 20.12 and 23 including 23.5, plus break-glass access from 14; merchant API authentication is not included
  issue: "#6"

- id: T6
  title: Write the delivery requirements (CI/CD, environments, promotion, hotfix pipeline, v* tags, zero manual actions, infrastructure tests)
  agent: docs-writer
  paths: ["docs/requirements/delivery.md"]
  depends_on: []
  provides: delivery requirements
  requires: []
  acceptance: AC2, AC3, AC6, AC7 and AC9 hold; covers sections 4 (delivery), 9, 14 zero manual actions, 18 infrastructure autotests, 27.5 and 27.6; D1 including the SemVer bump rule, the tagging workflow as the only creator, creation allowed and deletion denied, no build on a tag, changelog, SBOM and provenance attached; includes the on-demand snapshot step of the migration Job before every schema change (D3, section 17)
  issue: "#7"

- id: T7
  title: Write the policy, as-code and cost requirements
  agent: docs-writer
  paths: ["docs/requirements/policy-and-cost.md"]
  depends_on: []
  provides: policy and cost requirements
  requires: []
  acceptance: AC2, AC3, AC6, AC7 and AC9 hold; covers sections 10, 12 controls, 20 (the parts not in T3 to T5 and T8), the FinOps threshold of 21.5 and 22; limits cited from nfr.md; the policies of D2 and D3 (no stateful resource without a backup plan, no schema change without an available snapshot), the SCP allow list for us-east-1 and us-east-2, and the IAM deny of DynamoDB writes in us-east-1 and us-east-2 before the switch for every principal other than the replication service
  issue: "#8"

- id: T8
  title: Write the observability, scaling and testing requirements (alerts, monitoring as code, load, chaos, incident analysis)
  agent: docs-writer
  paths: ["docs/requirements/observability-and-testing.md"]
  depends_on: []
  provides: observability and testing requirements
  requires: []
  acceptance: AC2, AC3, AC6, AC7 and AC9 hold; covers sections 7, 8, 15, 25 and 20.6, citing the coverage targets of 25.2 and the fire-drill targets of 25.4 from nfr.md; includes the incident-analysis agent through Amazon Bedrock with read-only access (section 7), the backup alerts of D2, the Aurora lag alert, the 80% restore-duration alert of D4, the non-paging warm-up alert of D8, the quarterly test of a full switch, to us-east-1 and us-east-2 in turn
  issue: "#9"

- id: T9
  title: Write the traceability table
  agent: docs-writer
  paths: ["docs/requirements/traceability.md"]
  depends_on: [T1, T2, T3, T4, T5, T6, T7, T8]
  provides: traceability table
  requires: ["requirements overview", "numeric targets", "infrastructure requirements", "data and recovery requirements", "security and access requirements", "delivery requirements", "policy and cost requirements", "observability and testing requirements"]
  acceptance: AC1 and AC5 hold; tools/lint/srs-lint exits 0 on the whole directory; unnumbered parts of sections 1 and 8 have their own rows; one row per ADR of section 13; one row for the ADR of T11
  issue: "#10"

- id: T11
  title: Write the ADR of the region model (data replicated, compute from Terraform, plan B)
  agent: docs-writer
  paths: ["docs/adr/0017-recovery-region-data-replication.md"]
  depends_on: [T1]
  provides: availability and recovery ADR
  requires: ["requirements overview"]
  acceptance: AC12 holds; the ADR follows the MADR format of section 13 (context, options considered, decision D6 and D7, cost, review condition); it states which parts of ADR-004 and section 3 it supersedes and why managed RPO stays off; it cites the AWS page "Creating a headless Aurora DB cluster in a secondary Region"; the cost section gives a monthly delta estimate (warm standby removed against two continuous replica regions: Aurora Global storage and replicated I/O for every cluster, DynamoDB replicated writes, S3 replication with Replication Time Control, snapshot copies) and says whether it exceeds the 1,000 USD FinOps threshold
  issue: "#11"

- id: T10
  title: Confirm the first edition as the baseline
  agent: docs-writer
  paths: ["docs/requirements/srs.md", "docs/requirements/nfr.md", "docs/requirements/infrastructure.md", "docs/requirements/data-and-recovery.md", "docs/requirements/security-and-access.md", "docs/requirements/delivery.md", "docs/requirements/policy-and-cost.md", "docs/requirements/observability-and-testing.md", "docs/requirements/traceability.md"]
  depends_on: [T9, T11]
  provides: baseline
  requires: ["traceability table", "availability and recovery ADR"]
  acceptance: AC8 holds; the commit passes tools/lint/spec-gate; tools/lint/srs-lint exits 0
  issue: "#12"
```
