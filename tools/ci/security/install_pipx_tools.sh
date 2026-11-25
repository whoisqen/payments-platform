#!/usr/bin/env bash
# Installs pipx-backed scanners of mise.toml into the mise Python, not the runner's system Python (semgrep's protobuf fails on 3.14).
set -euo pipefail

usage() { echo "usage: $0 [--dry-run] pipx:<tool>..." >&2; exit 2; }
dry_run=false
if [ "${1:-}" = "--dry-run" ]; then dry_run=true; shift; fi
[ $# -ge 1 ] || usage

py=$(mise which python3 2>/dev/null) || { echo "::error::the mise python is not installed; add python to install_args of jdx/mise-action"; exit 1; }
want=$("$py" -c 'import sys; print("%d.%d" % sys.version_info[:2])')
# pipx and uv read these when mise builds the tool venv
export PIPX_DEFAULT_PYTHON="$py" UV_PYTHON="$py"

venv_python() {
  local dir cfg
  dir=$(mise where "$1" 2>/dev/null) || return 0
  cfg=$(find "$dir" -maxdepth 4 -name pyvenv.cfg -print -quit)
  [ -n "$cfg" ] || return 0
  sed -nE 's/^version(_info)?[[:space:]]*=[[:space:]]*([0-9]+\.[0-9]+).*/\2/p' "$cfg" | head -n 1
}

for tool in "$@"; do
  case $tool in pipx:*) ;; *) echo "::error::${tool} is not a pipx: tool"; exit 2 ;; esac
  have=$(venv_python "$tool")
  if [ "$have" = "$want" ]; then
    echo "${tool}: installed with Python ${have}"
  elif $dry_run; then
    echo "${tool}: would install with Python ${want} (now: ${have:-not installed})"
    continue
  else
    # an install built with another Python (an older cache, auto-install through a shim) is rebuilt
    if [ -n "$have" ]; then mise uninstall "$tool"; fi
    mise install "$tool"
    have=$(venv_python "$tool")
    if [ "$have" != "$want" ]; then
      echo "::error::${tool} was built with Python ${have:-unknown}, expected ${want}"
      exit 1
    fi
    echo "${tool}: installed with Python ${have}"
  fi
  bin=${tool#pipx:}
  if ! mise exec -- "$bin" --version >/dev/null 2>&1; then
    echo "::error::${bin} --version fails after install; see: mise exec -- ${bin} --version"
    mise exec -- "$bin" --version || true
    exit 1
  fi
done
