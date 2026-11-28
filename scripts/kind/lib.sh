#!/usr/bin/env bash
# Shared settings and helpers of scripts/kind; sourced, never run.
# shellcheck disable=SC2034
set -euo pipefail

KIND_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "${KIND_DIR}/../.." && pwd)
CLUSTER=${KIND_CLUSTER:-pay-local}
CONTEXT="kind-${CLUSTER}"
LOCAL_ENV=${LOCAL_ENV:-demo}
HELMFILE=${HELMFILE_PATH:-${ROOT}/deploy/local/helmfile.yaml}
NAMESPACE=${LOCAL_NAMESPACE:-payments}
# the edge Gateway accepts only its host name; *.localhost resolves to the loopback on Linux (add it to /etc/hosts elsewhere)
EDGE_URL=${EDGE_URL:-https://api.payments.localhost:8443}
LOCAL_REPO=${LOCAL_REPO:-pay.local}
SERVICES=(router drainer scheduler locker control-center smoke)
DRY_RUN=0

log() { printf '%s\n' "$*" >&2; }
die() { log "error: $*"; exit 1; }

# every mutation goes through run, so --dry-run prints the exact command instead
run() {
  if [ "$DRY_RUN" = 1 ]; then
    printf 'would run:' >&2
    printf ' %q' "$@" >&2
    printf '\n' >&2
  else
    "$@"
  fi
}

cluster_exists() { command -v kind >/dev/null && kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; }

# kubectl and helmfile always name the kind context, so a shared cluster in the kubeconfig is never touched
kc() { kubectl --context "$CONTEXT" "$@"; }

# ghcr.io/<owner>/<repo> of the origin remote, lower-cased as GHCR requires
ghcr_repo() {
  if [ -n "${GHCR_REPO:-}" ]; then printf '%s\n' "$GHCR_REPO"; return; fi
  local url path
  url=$(git -C "$ROOT" remote get-url origin)
  path=${url#*github.com[:/]}
  path=${path%.git}
  printf 'ghcr.io/%s\n' "$(tr '[:upper:]' '[:lower:]' <<<"$path")"
}

latest_version() {
  if [ -n "${VERSION:-}" ]; then printf '%s\n' "$VERSION"; return; fi
  git -C "$ROOT" tag --list 'v*' --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -n1 || true
}

# CA of the edge certificate: LOCAL_CA_FILE, else ca.crt of the Secret deploy/local issues the edge certificate from
edge_ca() {
  if [ -n "${LOCAL_CA_FILE:-}" ]; then printf '%s\n' "$LOCAL_CA_FILE"; return; fi
  local ns=${LOCAL_CA_NAMESPACE:-istio-system} name=${LOCAL_CA_SECRET:-pay-local-ca} out
  out=$(mktemp)
  if kc get secret "$name" --namespace "$ns" -o 'jsonpath={.data.ca\.crt}' 2>/dev/null | base64 -d >"$out" && [ -s "$out" ]; then
    printf '%s\n' "$out"
  else
    rm -f "$out"
  fi
}
