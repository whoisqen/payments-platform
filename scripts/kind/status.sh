#!/usr/bin/env bash
# Shows the nodes, releases, pods and edge health of the local cluster; reads only.
# usage: status.sh [--dry-run]
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
  log "cluster ${CLUSTER} does not exist; start it with make up"
  exit 1
fi
if [ "$DRY_RUN" = 1 ]; then
  log "read-only: would list nodes, helm releases and pods of ${CONTEXT} and probe ${EDGE_URL}/health"
  exit 0
fi
kc get nodes -o wide
echo
helm --kube-context "$CONTEXT" list --all-namespaces
echo
kc get pods --all-namespaces -o wide
echo
if kc top nodes >/dev/null 2>&1; then kc top nodes; echo; fi
curl_args=(-fsS -o /dev/null -w '%{http_code}\n' --max-time 5)
ca=$(edge_ca)
[ -n "$ca" ] && curl_args+=(--cacert "$ca")
printf 'edge %s/health: ' "$EDGE_URL"
if ! curl "${curl_args[@]}" "${EDGE_URL}/health"; then
  echo "not answering"
  exit 1
fi
