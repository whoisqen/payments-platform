#!/usr/bin/env bash
# Creates the kind cluster (or reuses it), provides the images and installs deploy/local with helmfile.
# usage: up.sh [--dry-run] [--build] [--version vX.Y.Z] [--env demo|ci] [--skip-prereqs]
#   default: released images ghcr.io/<owner>/<repo>/<service>:<version> (latest v* tag), pulled by the nodes
#   --build: images built from this checkout with docker buildx, one at a time, and loaded into the nodes
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

build=0
skip_prereqs=0
while [ $# -gt 0 ]; do
  case $1 in
    --dry-run) DRY_RUN=1 ;;
    --build) build=1 ;;
    --version) VERSION=${2:?--version needs a value}; shift ;;
    --env) LOCAL_ENV=${2:?--env needs a value}; shift ;;
    --skip-prereqs) skip_prereqs=1 ;;
    -h | --help) sed -n 2,5p "$0"; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done
[[ $LOCAL_ENV =~ ^(demo|ci)$ ]] || die "--env must be demo or ci"

if [ "$skip_prereqs" = 0 ]; then
  prereq_args=()
  [ "$build" = 1 ] && prereq_args+=(--build)
  "${KIND_DIR}/prereqs.sh" "${prereq_args[@]}" || die "fix the prerequisites above first"
fi
[ -f "$HELMFILE" ] || die "no ${HELMFILE#"${ROOT}/"}; the local deployment is not in this checkout"

if cluster_exists; then
  log "cluster ${CLUSTER} exists, reusing it"
else
  run kind create cluster --config "${KIND_DIR}/cluster.yaml" --name "$CLUSTER" --wait 180s
fi

values=()
if [ "$build" = 1 ]; then
  log "building ${#SERVICES[@]} images locally: the four Rust services need about 30 to 60 minutes each and up to 10 GiB of memory"
  mapfile -t common < <(sed 's/^/--build-arg=/' "${ROOT}/docker/_common/build-args.env")
  arch=$(docker version --format '{{.Server.Arch}}')
  for svc in "${SERVICES[@]}"; do
    # the last commit of the image inputs names the image, so an unchanged service is not rebuilt
    mapfile -t paths < <(python3 "${ROOT}/tools/ci/changed_images.py" --paths "$svc")
    sha=$(git -C "$ROOT" log -1 --format=%H -- "${paths[@]}")
    [ -n "$sha" ] || die "${svc}: no commit touches its inputs"
    tag="${sha:0:12}"
    ref="${LOCAL_REPO}/${svc}:${tag}"
    if docker image inspect "$ref" >/dev/null 2>&1; then
      log "${ref} exists, not rebuilt"
    else
      epoch=$(git -C "$ROOT" log -1 --format=%ct "$sha")
      run docker buildx build "${common[@]}" --file "${ROOT}/docker/${svc}/Dockerfile" --platform "linux/${arch}" \
        --provenance=false --sbom=false --build-arg "SOURCE_DATE_EPOCH=${epoch}" --build-arg "REVISION=${sha}" \
        --load --tag "$ref" "$ROOT"
    fi
    run kind load docker-image --name "$CLUSTER" "$ref"
    values+=("images.${svc}.repository=${LOCAL_REPO}/${svc}" "images.${svc}.tag=${tag}")
  done
else
  version=$(latest_version)
  [ -n "$version" ] || die "no v* tag in this checkout; set VERSION=vX.Y.Z or build locally with BUILD=1"
  repo=$(ghcr_repo)
  for svc in "${SERVICES[@]}"; do
    ref="${repo}/${svc}:${version}"
    if [ "$DRY_RUN" = 1 ]; then
      log "would resolve ${ref} to its digest"
      values+=("images.${svc}.repository=${repo}/${svc}" "images.${svc}.tag=${version}")
      continue
    fi
    # the nodes pull by digest, so a moved tag cannot change what runs
    digest=$(docker buildx imagetools inspect "$ref" --format '{{json .Manifest}}' 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["digest"])') ||
      die "${ref} is not published; pick another VERSION or build locally with BUILD=1"
    values+=("images.${svc}.repository=${repo}/${svc}" "images.${svc}.digest=${digest}")
  done
fi

set_values=$(IFS=,; echo "${values[*]}")
run helmfile --kube-context "$CONTEXT" -f "$HELMFILE" -e "$LOCAL_ENV" apply --wait --suppress-diff --state-values-set "$set_values"

cat >&2 <<EOF

The platform runs in kind cluster ${CLUSTER} (environment ${LOCAL_ENV}).
  edge (payments API):  ${EDGE_URL}
  health:               ${EDGE_URL}/health
  status:               make status
  logs:                 make logs SERVICE=router
  sample payment:       make demo
  remove everything:    make down
EOF
