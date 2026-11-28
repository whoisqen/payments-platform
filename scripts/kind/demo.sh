#!/usr/bin/env bash
# Runs the API scenarios of tests/integration through the edge: a merchant with the dummy connector, then a payment.
# usage: demo.sh [--dry-run]
#   EDGE_URL (default https://api.payments.localhost:8443); LOCAL_CA_FILE, else Secret LOCAL_CA_SECRET (default istio-system/pay-local-ca): edge CA;
#   INTEGRATION_ADMIN_API_KEY, else read from Secret ADMIN_KEY_SECRET (default router-vault) key ADMIN_KEY_FIELD in LOCAL_NAMESPACE
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

for a in "$@"; do
  case $a in
    --dry-run) DRY_RUN=1 ;;
    -h | --help) sed -n 2,5p "$0"; exit 0 ;;
    *) die "unknown option: $a" ;;
  esac
done

secret=${ADMIN_KEY_SECRET:-router-vault}
field=${ADMIN_KEY_FIELD:-ROUTER__SECRETS__ADMIN_API_KEY}
cluster_exists || die "cluster ${CLUSTER} does not exist; start it with make up"

if [ "$DRY_RUN" = 1 ]; then
  log "would read the admin key from secret ${NAMESPACE}/${secret} (${field}) unless INTEGRATION_ADMIN_API_KEY is set"
  log "would run tests/integration/run.py against ${EDGE_URL}"
  exit 0
fi

if [ -z "${INTEGRATION_ADMIN_API_KEY:-}" ]; then
  INTEGRATION_ADMIN_API_KEY=$(kc get secret "$secret" --namespace "$NAMESPACE" -o "jsonpath={.data.${field}}" | base64 -d) ||
    die "cannot read the admin key; set INTEGRATION_ADMIN_API_KEY or ADMIN_KEY_SECRET"
fi
export INTEGRATION_ADMIN_API_KEY
export INTEGRATION_API_URL=$EDGE_URL
# the local edge routes by the cell header; the local stack runs one cell
export INTEGRATION_CELL=${INTEGRATION_CELL:-cell-0}
# the edge certificate of the local stack is signed by a local CA, which Python must trust
ca=$(edge_ca)
if [ -n "$ca" ]; then export SSL_CERT_FILE=$ca; fi
python3 "${ROOT}/tests/integration/run.py"
