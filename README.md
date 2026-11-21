# payments-platform

Payment orchestrator based on Hyperswitch. The architecture is described in the document "Payments Platform: architecture and operations".

| Directory | Contents |
|---|---|
| `vendor/` | third-party code, unchanged (hyperswitch, card-vault, e2e tests) |
| `docker/` | service Dockerfiles |
| `infra/` | Terraform / Terragrunt |
| `deploy/` | Helm charts and ArgoCD |
| `policy/` | policies, IAM, tags, compliance, resilience |
| `observability/` | alerts, dashboards, SLOs |
| `tests/` | the platform's own tests |
| `scripts/` | operations scripts |
| `tools/` | linters and CI generators |
| `specs/` | change specifications |
| `docs/` | ADRs, runbooks, architecture |

## License

Original work is licensed under the Apache License 2.0 (see `LICENSE`), the same license as the upstream Hyperswitch code. Third-party code in `vendor/` keeps its own licenses (see `vendor/README.md`).
