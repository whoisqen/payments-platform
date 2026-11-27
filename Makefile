SHELL := bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help

# Terraform roots with their own tests; infra/modules does not exist yet and is skipped while empty.
TF_MODULES := $(sort $(dir $(wildcard infra/modules/*/main.tf infra/github/modules/*/main.tf)))
CHARTS := $(sort $(dir $(wildcard deploy/charts/*/Chart.yaml deploy/argocd/Chart.yaml)))
PY_TESTS := $(sort $(wildcard services/cell-copy/tests tools/ci/tests tools/ci/rust/tests tools/ci/compose/tests tools/ci/promote/tests tools/ci/infra/tests tools/ci/runbook/tests tools/ai/tests tools/lint/tests scripts/*/tests tests/smoke tests/e2e tests/contracts tests/component tests/integration observability/tests observability/slo/tests observability/lib/tests policy/scp/tests) tools/config/tests)
WORKFLOWS := $(wildcard .github/workflows/*.yml)
ENV ?= dev
# New linters start in report mode; LINT_STRICT=1 (CI: repository variable LINT_STRICT=true) makes their findings block.
LINT_STRICT ?= 0
export LINT_STRICT
REPORT := tools/ci/lint/report.sh
TF_ROOTS := $(sort $(dir $(wildcard infra/modules/*/main.tf infra/github/main.tf infra/github/modules/*/main.tf)))

.PHONY: help bootstrap lint test plan render image-amd64 lint-workflows lint-migrations lint-docker lint-terraform lint-helm lint-python lint-secrets lint-repo \
	lint-report lint-ruff lint-yaml lint-tflint lint-kube test-python test-terraform test-helm test-policy test-alerts test-node \
	component integration

help:
	@grep -E '^[a-z0-9-]+:.*## ' $(MAKEFILE_LIST) | sed 's/:.*## /\t/'

bootstrap: ## install the pinned tools from mise.toml and the git hooks
	command -v mise >/dev/null || { echo "install mise first: https://mise.jdx.dev"; exit 1; }
	mise install
	git config core.hooksPath tools/scripts/git-hooks

lint: lint-repo lint-workflows lint-migrations lint-docker lint-terraform lint-helm lint-python lint-secrets lint-report ## every static check CI runs

lint-repo:
	tools/lint/spec-lint
	tools/lint/structure
	python3 tools/config/validate.py
	python3 observability/lib/build.py --check
	python3 observability/lib/gen_resilience.py --check
	python3 observability/slo/generate.py --check
	python3 tools/config/render --check

render: ## rewrite every file generated from config/platform.yaml (tools/config generators)
	python3 tools/config/render

lint-workflows:
	actionlint $(WORKFLOWS)

lint-migrations: ## migrations added or changed against origin/main
	python3 tools/ci/migrations/migration_check.py check --base origin/main --head HEAD

lint-docker:
	python3 tools/ci/dockerfile_check.py
	python3 tools/ci/buildkit/buildkit_pin_check.py
	shellcheck docker/_common/collect-libs.sh docker/migrator/*.sh scripts/*/*.sh tools/ci/runbook/*.sh
	@if command -v hadolint >/dev/null; then hadolint --failure-threshold warning --ignore DL3008 docker/*/Dockerfile; else echo "skip hadolint: not installed"; fi
	@if [ -d policy/opa/docker ]; then conftest test --policy policy/opa/docker docker/*/Dockerfile; else echo "skip conftest: policy/opa/docker does not exist"; fi

lint-terraform:
	terraform fmt -check -recursive infra
	@for d in $(TF_MODULES); do terraform -chdir=$$d init -backend=false -input=false >/dev/null && terraform -chdir=$$d validate; done

lint-helm:
	@if [ -z "$(CHARTS)" ]; then echo "skip helm: deploy/charts is empty"; exit 0; fi
	@for c in $(CHARTS); do \
		f=$$c/ci/lint-values.yaml; v=""; [ -f $$f ] && v="-f $$f"; \
		helm dependency build $$c >/dev/null || exit 1; \
		helm lint $$c $$v || exit 1; \
		grep -q '^type: library' $$c/Chart.yaml || helm template $$c $$v | kubeconform -strict -ignore-missing-schemas -summary || exit 1; \
	done

lint-python:
	python3 -m py_compile $$(find tools scripts -name '*.py' -not -path '*/node_modules/*')

lint-secrets:
	gitleaks detect --no-banner --redact --config .github/gitleaks.toml

lint-report: lint-ruff lint-yaml lint-tflint lint-kube ## the linters in report mode (LINT_STRICT=1 blocks)

lint-ruff:
	$(REPORT) ruff -- ruff check --no-cache --config tools/ci/lint/ruff.toml $(if $(GITHUB_ACTIONS),--output-format github) .

lint-yaml:
	$(REPORT) yamllint -- yamllint -c tools/ci/lint/yamllint.yaml $(if $(GITHUB_ACTIONS),-f github) .github deploy policy observability docker tools tests

lint-tflint:
	@$(REPORT) tflint-init -- tflint --init --config=$(CURDIR)/tools/ci/lint/tflint.hcl
	@for d in $(TF_ROOTS); do \
		$(REPORT) "tflint-$$d" -- tflint --chdir=$$d --config=$(CURDIR)/tools/ci/lint/tflint.hcl $(if $(GITHUB_ACTIONS),--format=compact) || exit 1; \
	done

lint-kube:
	@if [ -z "$(CHARTS)" ]; then echo "skip kube-linter: no charts"; exit 0; fi
	@out=$$(mktemp -d); for c in $(CHARTS); do \
		if grep -q '^type: library' $$c/Chart.yaml; then continue; fi; \
		f=$$c/ci/lint-values.yaml; v=""; [ -f $$f ] && v="-f $$f"; \
		helm dependency build $$c >/dev/null || exit 1; \
		helm template $$c $$v >$$out/$$(basename $$c).yaml || exit 1; \
	done; $(REPORT) kube-linter -- kube-linter lint --config tools/ci/lint/kube-linter.yaml $$out

test: test-python test-terraform test-helm test-policy test-alerts test-node ## every offline test CI runs

test-python:
	@for d in $(PY_TESTS); do python3 -m unittest discover -s $$d; done

test-terraform:
	@for d in $(TF_MODULES); do [ -d $$d/tests ] || continue; terraform -chdir=$$d init -backend=false -input=false >/dev/null && terraform -chdir=$$d test; done

test-helm:
	@if [ -z "$(CHARTS)" ]; then echo "skip helm unittest: deploy/charts is empty"; exit 0; fi
	@for c in $(CHARTS); do \
		if [ ! -d $$c/tests ]; then continue; fi; \
		helm dependency build $$c >/dev/null && helm unittest -f 'tests/*_test.yaml' -f 'tests/*/*_test.yaml' $$c || exit 1; \
	done

test-policy:
	@if [ -d policy/opa ]; then opa test policy/opa -v; else echo "skip opa: policy/opa does not exist"; fi
	opa test policy/tagging policy/scp/tag-policies
	@if [ -d policy/kyverno ]; then kyverno test policy/kyverno; else echo "skip kyverno: policy/kyverno does not exist"; fi

test-alerts:
	python3 observability/tests/run.py

test-node:
	cd tests/load && node --test tests/*.test.mjs

component: ## component check of built binaries in COMPONENT_<NAME>_BIN; e.g. make component SERVICES="router drainer"
	python3 tests/component/run.py $(or $(SERVICES),router drainer scheduler locker) --logs $(or $(LOGS),component-logs)

integration: ## API scenarios against INTEGRATION_API_URL (docker/compose for a local stack)
	python3 tests/integration/run.py

plan: ## terraform plan of every component of ENV (default dev); needs AWS credentials of the plan role
	@if [ ! -d infra/live/$(ENV) ]; then echo "skip plan: infra/live/$(ENV) does not exist"; exit 0; fi
	cd infra/live/$(ENV) && terragrunt run --all --non-interactive -- plan -lock=false

image-amd64: ## developer image for a laptop, loaded into the local docker; usage: make image-amd64 SERVICE=router
	@test -n "$(SERVICE)" || { echo "SERVICE is required"; exit 2; }
	docker buildx build --platform linux/amd64 -f docker/$(SERVICE)/Dockerfile --load -t dev/$(SERVICE):local \
		--build-arg SOURCE_DATE_EPOCH=$$(git log -1 --format=%ct) .

# Local runs of the blocking gates of .github/workflows/security.yml; outputs go to a fresh mktemp directory.
.PHONY: security test-semgrep security-semgrep security-iac security-deps security-licenses security-workflows

security: test-semgrep security-semgrep security-iac security-deps security-licenses security-workflows ## blocking DevSecOps gates of security.yml

test-semgrep: ## tests of the repo Semgrep rules in policy/semgrep
	semgrep --test --metrics=off policy/semgrep

security-semgrep:
	@out=$$(mktemp -d); \
		semgrep scan --metrics=off $$(python3 tools/ci/security/gates.py semgrep-args policy/security/code/semgrep.toml) --sarif --output "$$out/semgrep.sarif" .; \
		python3 tools/ci/security/gates.py sarif-gate policy/security/code/semgrep.toml "$$out/semgrep.sarif"

security-iac:
	@out=$$(mktemp -d); cp -r infra docker "$$out/"; tools/ci/security/render_charts.sh "$$out/rendered"; \
		trivy config --config policy/security/iac/trivy-config.yaml --ignorefile policy/security/trivyignore.yaml --tf-exclude-downloaded-modules "$$out"; \
		cd "$$out" && checkov --config-file "$(CURDIR)/policy/security/iac/checkov.yaml" -d infra -d rendered

security-deps:
	trivy fs --config policy/security/deps/trivy-vuln.yaml --ignorefile policy/security/trivyignore.yaml .

security-licenses:
	@out=$$(mktemp -d); \
		syft scan dir:. --exclude './**/Cargo.lock' --exclude './**/target/**' --exclude './**/node_modules/**' -o "cyclonedx-json=$$out/sbom.json"; \
		for ws in hyperswitch card-vault; do cargo metadata --format-version 1 --locked --manifest-path "vendor/$$ws/Cargo.toml" >"$$out/cargo-$$ws.json"; done; \
		python3 tools/ci/security/license_check.py --policy policy/security/deps/licenses.toml --cyclonedx "$$out/sbom.json" \
			--cargo-metadata "$$out/cargo-hyperswitch.json" --cargo-metadata "$$out/cargo-card-vault.json"

security-workflows:
	zizmor --config policy/security/workflows/zizmor.yml --min-severity "$$(python3 tools/ci/security/gates.py get policy/security/workflows/zizmor-gate.toml min_severity)" .github
