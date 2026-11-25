# security

Thresholds and waivers of the DevSecOps scanners run by `.github/workflows/security.yml`, one directory per concern: `code/` (Semgrep, CodeQL), `iac/` (Checkov, Trivy config), `deps/` (Trivy vulnerabilities, cargo-deny, dependency review, licenses), `workflows/` (zizmor), `dast/` (ZAP baseline); `trivyignore.yaml` holds the Trivy waivers.

Only these block: secrets, high or critical vulnerabilities with a fix, high or critical IaC findings, high zizmor findings, a license on the deny list, the repo Semgrep rules and ERROR registry rules. Everything else goes to code scanning and the job summary.

Every waiver names a reason (`statement` for Trivy, a trailing comment for Checkov); `tools/ci/tests/security` enforces it and keeps the license lists of `deps/licenses.toml`, `deps/deny.toml` and `deps/dependency-review.yml` in sync.
