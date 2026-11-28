#!/usr/bin/env bash
# Prints recent logs of one service, or exports every node and pod log of the cluster to a directory.
# usage: logs.sh [--dry-run] [SERVICE] [--since 15m] [--export DIR]
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

service=""
since=15m
export_dir=""
while [ $# -gt 0 ]; do
  case $1 in
    --dry-run) DRY_RUN=1 ;;
    --since) since=${2:?--since needs a value}; shift ;;
    --export) export_dir=${2:?--export needs a directory}; shift ;;
    -h | --help) sed -n 2,3p "$0"; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *) service=$1 ;;
  esac
  shift
done

cluster_exists || die "cluster ${CLUSTER} does not exist"

if [ -n "$export_dir" ]; then
  run mkdir -p "$export_dir"
  run kind export logs --name "$CLUSTER" "$export_dir/kind"
  if [ "$DRY_RUN" = 0 ]; then
    kc get pods --all-namespaces -o wide >"$export_dir/pods.txt" || true
    kc get events --all-namespaces --sort-by=.lastTimestamp >"$export_dir/events.txt" || true
    kc describe pods --all-namespaces >"$export_dir/describe-pods.txt" || true
  fi
  log "logs exported to ${export_dir}"
  exit 0
fi

if [ -z "$service" ]; then
  log "services: ${SERVICES[*]}; usage: logs.sh SERVICE [--since 15m]"
  exit 2
fi
[[ " ${SERVICES[*]} " == *" ${service} "* ]] || die "unknown service: ${service}"
if [ "$DRY_RUN" = 1 ]; then
  log "read-only: would print the last ${since} of pods labelled app.kubernetes.io/name=${service}"
  exit 0
fi
kc logs --all-namespaces --selector "app.kubernetes.io/name=${service}" --all-containers --prefix --since "$since" --tail 500
