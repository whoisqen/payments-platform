SHELL := bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help

# Terraform roots with their own tests; infra/modules does not exist yet and is skipped while empty.
TF_MODULES := $(sort $(dir $(wildcard infra/modules/*/main.tf infra/github/modules/*/main.tf)))
CHARTS := $(sort $(dir $(wildcard deploy/charts/*/Chart.yaml deploy/argocd/Chart.yaml)))
PY_TESTS := $(sort $(wildcard tools/ci/tests tools/lint/tests scripts/*/tests tests/smoke tests/e2e tests/contracts) tools/config/tests)
WORKFLOWS := $(wildcard .github/workflows/*.yml)
ENV ?= dev

.PHONY: help bootstrap lint test plan image-amd64 lint-workflows lint-docker lint-terraform lint-helm lint-python lint-secrets lint-repo \
	test-python test-terraform test-helm test-policy

help:
	@grep -E '^[a-z0-9-]+:.*## ' $(MAKEFILE_LIST) | sed 's/:.*## /\t/'

bootstrap: ## install the pinned tools from mise.toml and the git hooks
	command -v mise >/dev/null || { echo "install mise first: https://mise.jdx.dev"; exit 1; }
	mise install
	git config core.hooksPath tools/scripts/git-hooks

lint: lint-repo lint-workflows lint-docker lint-terraform lint-helm lint-python lint-secrets ## every static check CI runs

lint-repo:
	tools/lint/spec-lint
	tools/lint/structure
	python3 tools/config/validate.py
	python3 tools/config/render_standby.py --check
	python3 tools/config/render_central.py --check
	python3 tools/config/render_vault.py --check

lint-workflows:
	actionlint $(WORKFLOWS)

lint-docker:
	python3 tools/ci/dockerfile_check.py
	shellcheck docker/_common/collect-libs.sh scripts/*/*.sh
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

test: test-python test-terraform test-helm test-policy ## every offline test CI runs

test-python:
	@for d in $(PY_TESTS); do python3 -m unittest discover -s $$d; done

test-terraform:
	@for d in $(TF_MODULES); do [ -d $$d/tests ] || continue; terraform -chdir=$$d init -backend=false -input=false >/dev/null && terraform -chdir=$$d test; done

test-helm:
	@if [ -z "$(CHARTS)" ]; then echo "skip helm unittest: deploy/charts is empty"; exit 0; fi
	@for c in $(CHARTS); do [ -d $$c/tests ] && helm unittest $$c; done

test-policy:
	@if [ -d policy/opa ]; then opa test policy/opa -v; else echo "skip opa: policy/opa does not exist"; fi
	@if [ -d policy/kyverno ]; then kyverno test policy/kyverno; else echo "skip kyverno: policy/kyverno does not exist"; fi

plan: ## terraform plan of every component of ENV (default dev); needs AWS credentials of the plan role
	@if [ ! -d infra/live/$(ENV) ]; then echo "skip plan: infra/live/$(ENV) does not exist"; exit 0; fi
	cd infra/live/$(ENV) && terragrunt run --all --non-interactive -- plan -lock=false

image-amd64: ## developer image for a laptop, loaded into the local docker; usage: make image-amd64 SERVICE=router
	@test -n "$(SERVICE)" || { echo "SERVICE is required"; exit 2; }
	docker buildx build --platform linux/amd64 -f docker/$(SERVICE)/Dockerfile --load -t dev/$(SERVICE):local \
		--build-arg SOURCE_DATE_EPOCH=$$(git log -1 --format=%ct) .
