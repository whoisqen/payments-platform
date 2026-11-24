#!/usr/bin/env bash
# Installs the hash-pinned requirements of the AI review. Without tools/ai/requirements.txt the review is switched off, never run unpinned.
set -euo pipefail
cd "$(dirname "$0")"
if [ ! -s requirements.txt ]; then
  echo "::warning::tools/ai/requirements.txt is missing; the AI review is off until the hashed lock file is added (tools/ai/README.md)"
  echo "ready=false" >> "${GITHUB_OUTPUT:-/dev/null}"
  exit 0
fi
# An advisory review must never turn the pull request red: a failed install switches the review off with a warning
if ! python3 -m pip install --quiet --require-hashes --no-deps --only-binary=:all: -r requirements.txt; then
  echo "::warning::the hashed requirements of the AI review could not be installed; the review is off for this run"
  echo "ready=false" >> "${GITHUB_OUTPUT:-/dev/null}"
  exit 0
fi
echo "ready=true" >> "${GITHUB_OUTPUT:-/dev/null}"
