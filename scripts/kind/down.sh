#!/usr/bin/env bash
# Deletes the kind cluster with everything in it; a missing cluster is not an error.
# usage: down.sh [--dry-run]
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

for a in "$@"; do
  case $a in
    --dry-run) DRY_RUN=1 ;;
    -h | --help) sed -n 2,3p "$0"; exit 0 ;;
    *) die "unknown option: $a" ;;
  esac
done

if ! cluster_exists; then
  log "cluster ${CLUSTER} does not exist, nothing to delete"
  exit 0
fi
run kind delete cluster --name "$CLUSTER"
