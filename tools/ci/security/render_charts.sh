#!/usr/bin/env bash
# Renders every application chart under deploy/charts with its ci/lint-values.yaml into OUT_DIR/<chart>.yaml for the IaC scanners.
set -euo pipefail

usage() { echo "usage: $0 [--dry-run] OUT_DIR" >&2; exit 2; }
dry_run=false
if [ "${1:-}" = "--dry-run" ]; then dry_run=true; shift; fi
[ $# -eq 1 ] || usage
out=$1
root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)

$dry_run || mkdir -p "$out"
count=0
for chart in "$root"/deploy/charts/*/; do
  chart=${chart%/}
  name=$(basename "$chart")
  [ -f "$chart/Chart.yaml" ] || continue
  # a library chart renders nothing on its own
  if grep -q '^type: library' "$chart/Chart.yaml"; then continue; fi
  values=()
  [ -f "$chart/ci/lint-values.yaml" ] && values=(-f "$chart/ci/lint-values.yaml")
  if $dry_run; then
    echo "would render ${name} ${values[*]:-(default values)} to ${out}/${name}.yaml"
  else
    # dependencies are file:// charts of this repo; the build is skipped when charts/ already matches Chart.lock
    helm dependency build --skip-refresh "$chart" >/dev/null
    helm template "$name" "$chart" "${values[@]}" >"$out/${name}.yaml"
  fi
  count=$((count + 1))
done
suffix=""
if $dry_run; then suffix=" (dry run)"; fi
echo "render_charts: ${count} chart(s)${suffix}"
