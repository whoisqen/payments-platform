# Documentation

The payments platform is a multi-tenant payment orchestrator on Hyperswitch, running on AWS in cells, with card data held only in the locker. This directory explains how it is built, how it is run and how it is kept secure.

## Reading order

**Newcomer** (one hour):

1. [Architecture overview](architecture/README.md): the request path from merchant to PSP, cells, locker, edge, data, regions.
2. [Glossary](glossary.md): the words used everywhere else.
3. [Services, configuration and secrets](architecture/runtime/services-secrets.md).
4. [Disaster recovery](dr/README.md): what happens when a region fails.

**Engineer** (changing code or infrastructure):

1. [Kubernetes and Argo CD delivery](architecture/foundation/kubernetes-delivery.md): how a change reaches each environment.
2. [CI/CD stages and security scans](architecture/delivery/cicd-security.md): what runs on a pull request and what blocks it.
3. [Configuration and generators](architecture/foundation/configuration.md): where values live and which files are generated.
4. [AWS accounts and network](architecture/foundation/aws-accounts-network.md), [data stores and backups](architecture/foundation/data-backups.md).
5. [AI review and the admin AI agent](architecture/delivery/ai.md), [chaos and load testing](architecture/delivery/chaos-load.md).
6. Change specifications in `specs/`, the requirements in [requirements/](requirements/README.md).

**Operator** (on call):

1. [Observability and alerting](architecture/runtime/observability.md), including the slow requests view.
2. Runbooks in `runbooks/`, one per alert, grouped by layer.
3. [Edge](architecture/runtime/edge.md) and [rate limiting and load shedding](architecture/runtime/rate-limiting.md).
4. [Failover and failback](dr/failover.md), [drills](dr/drills.md).
5. [Capacity model](capacity/README.md), [chaos catalog](chaos/README.md).

**Auditor** (PCI DSS and controls):

1. [Security controls](security/README.md): CDE isolation, zero trust, identity, SCPs, secrets, scanning, incident response.
2. [Threat model](security/threat-model.md), including the CI pull request perimeter.
3. [AWS accounts and network](architecture/foundation/aws-accounts-network.md): OUs, guardrails, egress control.
4. [Data stores and backups](architecture/foundation/data-backups.md) and [disaster recovery](dr/README.md): retention, restore tests, recovery objectives.
5. [Cost and FinOps](architecture/cost/README.md).

## Layout

| Directory | Contents |
|---|---|
| `architecture/` | Overview and one page per subsystem; `cost/` for cost and FinOps |
| `security/` | Controls and threat model |
| `dr/` | Warm standby, failover, drills |
| `runbooks/` | One runbook per alert or operation |
| `adr/` | Architecture decision records |
| `requirements/` | Software requirements specification |
| `capacity/`, `chaos/` | Capacity model, chaos experiment catalog |
| `glossary.md` | Canonical terms |

Architecture and DR pages follow one pattern: what it is, why, how it works, where in the repo.
