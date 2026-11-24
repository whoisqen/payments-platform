#!/usr/bin/env bash
# Installs the hash-pinned requirements of the AI review. Without tools/ai/requirements.txt the review is switched off, never run unpinned.
set -euo pipefail
cd "$(dirname "$0")"
if [ ! -s requirements.txt ]; then
  echo "::warning::tools/ai/requirements.txt is missing; the AI review is off until the hashed lock file is added (tools/ai/README.md)"
  echo "ready=false" >> "${GITHUB_OUTPUT:-/dev/null}"
  exit 0
fi
python3 -m pip install --quiet --require-hashes --no-deps --only-binary=:all: -r requirements.txt
echo "ready=true" >> "${GITHUB_OUTPUT:-/dev/null}"
