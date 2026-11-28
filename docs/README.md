# Documentation

The payments platform is a multi-tenant payment orchestrator on Hyperswitch, running on AWS in cells, with card data held only in the locker. This directory explains how it is built, how it is run and how it is kept secure.

## Reading order

**Newcomer** (one hour):

1. [Payments in 10 minutes](architecture/domain/README.md): the subject area for readers new to card payments: who takes part in a payment, its lifecycle, card data and PCI DSS, and the platform's own concepts.
2. [Architecture overview](architecture/README.md): the request path from merchant to PSP, cells, locker, edge, data, regions.
3. [Glossary](glossary.md): the words used everywhere else.
4. [Services and stores](architecture/services/README.md) and the [walkthrough of one card payment](architecture/services/card-payment-walkthrough.md): what each service and database does.
5. [Services, configuration and secrets](architecture/runtime/services-secrets.md).
6. [Disaster recovery](dr/README.md): what happens when a region fails.

**Engineer** (changing code or infrastructure):

1. Local cluster: `make up` runs the platform on kind, `make demo` sends a payment through the local edge ([scripts/kind](../scripts/kind/README.md), [deploy/local](../deploy/local/README.md)).
2. [Kubernetes and Argo CD delivery](architecture/foundation/kubernetes-delivery.md): how a change reaches each environment.
3. [CI/CD stages and security scans](architecture/delivery/cicd-security.md): what runs on a pull request and what blocks it.
4. [Configuration and generators](architecture/foundation/configuration.md): where values live and which files are generated.
5. [Infrastructure](architecture/infrastructure/README.md): what is built in AWS, unit by unit, and how to change it; start with [infrastructure as code](architecture/infrastructure/base/iac.md).
6. [AWS accounts and network](architecture/foundation/aws-accounts-network.md), [data stores and backups](architecture/foundation/data-backups.md).
7. [AI review and the admin AI agent](architecture/delivery/ai.md), [chaos and load testing](architecture/delivery/chaos-load.md).
8. Change specifications in `specs/`, the requirements in [requirements/](requirements/README.md).

**Operator** (on call):

1. [Observability and alerting](architecture/runtime/observability.md), including the slow requests view.
2. [Logging](architecture/runtime/logging.md): where logs live in OpenSearch, how to read them, shards and retention.
3. Runbooks in `runbooks/`, one per alert, grouped by layer.
4. [Edge](architecture/runtime/edge.md) and [rate limiting and load shedding](architecture/runtime/rate-limiting.md).
5. [Deploying the platform](architecture/operations/deploy.md) and [day-2 operations](architecture/operations/day-2.md): first rollout, new cells, rotation, EKS upgrades, scaling.
6. [Failover and failback](dr/failover.md), [drills](dr/drills.md), and the infrastructure behind them in [regions and disaster recovery](architecture/infrastructure/support/dr.md).
7. [Capacity model](capacity/README.md), [chaos catalog](chaos/README.md).

**Auditor** (PCI DSS and controls):

1. [Security controls](security/README.md): CDE isolation, zero trust, identity, SCPs, secrets, scanning, incident response.
2. [Threat model](security/threat-model.md), including the CI pull request perimeter.
3. [AWS accounts and network](architecture/foundation/aws-accounts-network.md): OUs, guardrails, egress control.
4. [Data stores and backups](architecture/foundation/data-backups.md) and [disaster recovery](dr/README.md): retention, restore tests, recovery objectives.
5. [Cost and FinOps](architecture/cost/README.md).

## Layout

| Directory | Contents |
|---|---|
| `architecture/` | Overview and one page per subsystem; `domain/` for the payments primer; `services/` for every service and store; `infrastructure/` for what is built in AWS; `operations/` for deployment and day-2 work; `cost/` for cost and FinOps |
| `security/` | Controls and threat model |
| `dr/` | Hot standby in us-east-1, failover, game days |
| `runbooks/` | One runbook per alert or operation |
| `adr/` | Architecture decision records |
| `requirements/` | Software requirements specification |
| `capacity/`, `chaos/` | Capacity model, chaos experiment catalog |
| `glossary.md` | Canonical terms |

Architecture and DR pages follow one pattern: what it is, why, how it works, where in the repo.
