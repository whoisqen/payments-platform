#!/usr/bin/env bash
# Checks the tools and free resources the local cluster needs and prints every gap; changes nothing.
# usage: prereqs.sh [--dry-run] [--build]   (--build applies the thresholds of local image builds)
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

build=0
for a in "$@"; do
  case $a in
    --dry-run) DRY_RUN=1 ;;
    --build) build=1 ;;
    -h | --help) sed -n 2,3p "$0"; exit 0 ;;
    *) die "unknown option: $a" ;;
  esac
done

# released images: two nodes plus the stack; local builds add four Rust release builds run one at a time
MIN_RAM_GIB=${MIN_RAM_GIB:-$([ "$build" = 1 ] && echo 12 || echo 8)}
MIN_DISK_GIB=${MIN_DISK_GIB:-$([ "$build" = 1 ] && echo 60 || echo 20)}
missing=0

# mapfile and empty arrays under set -u need bash 4.4; macOS ships 3.2 (brew install bash)
if [ "${BASH_VERSINFO[0]}" -lt 4 ] || { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -lt 4 ]; }; then
  echo "OLD      bash      ${BASH_VERSION}, needs 4.4 or newer"
  missing=$((missing + 1))
fi

need() {
  local name=$1 min=$2 have=$3 hint=${4:-mise install $1}
  if [ -z "$have" ]; then
    printf 'MISSING  %-9s needs %s or newer (%s)\n' "$name" "$min" "$hint"
    missing=$((missing + 1))
  elif [ "$(printf '%s\n%s\n' "$min" "$have" | sort -V | head -n1)" != "$min" ]; then
    printf 'OLD      %-9s %s, needs %s or newer\n' "$name" "$have" "$min"
    missing=$((missing + 1))
  else
    printf 'ok       %-9s %s\n' "$name" "$have"
  fi
}

ver() { grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true; }

docker_v=""
if command -v docker >/dev/null; then docker_v=$(docker version --format '{{.Server.Version}}' 2>/dev/null | ver); fi
need docker 24.0.0 "$docker_v"
need kind 0.33.0 "$(command -v kind >/dev/null && kind version | ver)"
need kubectl 1.36.0 "$(command -v kubectl >/dev/null && kubectl version --client 2>/dev/null | ver)"
need helm 3.14.0 "$(command -v helm >/dev/null && helm version --short 2>/dev/null | ver)"
need helmfile 1.0.0 "$(command -v helmfile >/dev/null && helmfile --version 2>/dev/null | ver)"
diff_v=""
if command -v helm >/dev/null; then diff_v=$(helm plugin list 2>/dev/null | awk '$1 == "diff" {print $2}' | ver); fi
need helm-diff 3.9.0 "$diff_v" "helmfile apply needs it: make bootstrap"

if [ "$build" = 1 ]; then
  if docker buildx version >/dev/null 2>&1; then echo "ok       buildx"; else echo "MISSING  buildx (docker buildx plugin)"; missing=$((missing + 1)); fi
fi

if [ -r /proc/meminfo ]; then
  ram_kib=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
elif command -v sysctl >/dev/null; then
  # macOS: Docker Desktop has its own VM limit, checked below through docker info
  ram_kib=$(($(sysctl -n hw.memsize) / 1024))
else
  ram_kib=0
fi
ram_gib=$((ram_kib / 1024 / 1024))
if [ -n "$docker_v" ]; then
  vm_gib=$(($(docker info --format '{{.MemTotal}}') / 1024 / 1024 / 1024))
  [ "$vm_gib" -lt "$ram_gib" ] && ram_gib=$vm_gib
fi
if [ "$ram_gib" -ge "$MIN_RAM_GIB" ]; then
  echo "ok       memory    ${ram_gib} GiB available (needs ${MIN_RAM_GIB})"
else
  echo "LOW      memory    ${ram_gib} GiB available, needs ${MIN_RAM_GIB}; close other workloads or raise the Docker VM limit"
  missing=$((missing + 1))
fi

# images and node disks live under the Docker root, which can be another partition than /
disk_dir=/
if [ -n "$docker_v" ]; then disk_dir=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || echo /); fi
[ -d "$disk_dir" ] || disk_dir=/
disk_gib=$(df -Pk "$disk_dir" | awk 'NR == 2 {print int($4 / 1024 / 1024)}')
if [ "$disk_gib" -ge "$MIN_DISK_GIB" ]; then
  echo "ok       disk      ${disk_gib} GiB free in ${disk_dir} (needs ${MIN_DISK_GIB})"
else
  echo "LOW      disk      ${disk_gib} GiB free in ${disk_dir}, needs ${MIN_DISK_GIB}"
  missing=$((missing + 1))
fi

if [ "$missing" -gt 0 ]; then
  echo "prereqs: ${missing} problem(s); 'make bootstrap' installs the pinned kind, kubectl, helm and helmfile"
  exit 1
fi
echo "prereqs: ok"
