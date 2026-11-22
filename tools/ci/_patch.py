def sub(path, old, new, count=1):
    s = open(path).read()
    assert old in s, (path, old[:50])
    open(path, "w").write(s.replace(old, new, count))


im = ".github/workflows/images.yml"
sub(im, '''    permissions:
      contents: read
    outputs:
      services: ${{ steps.pick.outputs.services }}''', '''    permissions:
      contents: read
      actions: read
    outputs:
      services: ${{ steps.pick.outputs.services }}''')
sub(im, '''          BEFORE_SHA: ${{ github.event.before }}
          AFTER_SHA: ${{ github.sha }}
        run: |''', '''          BEFORE_SHA: ${{ github.event.before }}
          AFTER_SHA: ${{ github.sha }}
          BRANCH: ${{ github.ref_name }}
          REPO: ${{ github.repository }}
          GH_TOKEN: ${{ github.token }}
        run: |''')
sub(im, '''            services=$(python3 tools/ci/changed_images.py --base "$BEFORE_SHA" --head "$AFTER_SHA" | jq -c .images)''', '''            # the concurrency group can drop a pending run, so the base is the last green run and not the previous push
            base=$(gh run list --repo "$REPO" --workflow images.yml --branch "$BRANCH" --status success --limit 1 --json headSha --jq '.[0].headSha // empty')
            if [ -z "$base" ] && [ -n "$BEFORE_SHA" ] && [[ ! $BEFORE_SHA =~ ^0+$ ]]; then base=$BEFORE_SHA; fi
            if [ -z "$base" ] && [ "$BRANCH" != main ]; then base=$(git merge-base "$AFTER_SHA" origin/main); fi
            args=(--head "$AFTER_SHA")
            if [ -n "$base" ]; then args+=(--base "$base"); fi
            services=$(python3 tools/ci/changed_images.py "${args[@]}" | jq -c .images)''')
sub(im, "            --platform \"$PLATFORMS\" \\\n", "            --platform \"$PLATFORMS\" \\\n            --provenance=false --sbom=false \\\n")

s = open(im).read()
start = s.index("      - name: sbom\n")
end = s.index("      - name: record the digest")
new = '''      - name: sbom
        run: syft "${IMAGE}@${DIGEST}" -o "cyclonedx-json=$RUNNER_TEMP/sbom.cdx.json"
      - name: already signed by this workflow
        id: signed
        env:
          REPO: ${{ github.repository }}
        run: |
          # the signature is pushed last, so its presence means sbom and provenance were attached by an earlier run
          ref="${IMAGE}@${DIGEST}"
          if cosign verify --certificate-identity-regexp "^https://github.com/${REPO}/.github/workflows/images.yml@.*$" \\
            --certificate-oidc-issuer https://token.actions.githubusercontent.com "$ref" >/dev/null 2>&1; then
            echo "done=true" >>"$GITHUB_OUTPUT"
          fi
      - name: attach the sbom
        if: steps.signed.outputs.done != 'true'
        run: cosign attest --yes --type cyclonedx --predicate "$RUNNER_TEMP/sbom.cdx.json" "${IMAGE}@${DIGEST}"
      - uses: actions/attest-build-provenance@e8998f949152b193b063cb0ec769d69d929409be # v2.4.0
        if: steps.signed.outputs.done != 'true'
        with:
          subject-name: ${{ env.IMAGE }}
          subject-digest: ${{ env.DIGEST }}
          push-to-registry: true
      - name: sign
        if: steps.signed.outputs.done != 'true'
        run: cosign sign --yes "${IMAGE}@${DIGEST}"
'''
s = s[:start] + new + s[end:]
open(im, "w").write(s)

sub(".github/workflows/nightly.yml", '--build-arg "SOURCE_URL=${REPO_URL}" \\\n', '--build-arg "SOURCE_URL=${REPO_URL}" \\\n            --provenance=false --sbom=false \\\n')

for svc in ("router", "drainer", "scheduler"):
    p = f"docker/{svc}/Dockerfile"
    sub(p, '''# protoc is needed by crates/external_services/build.rs, libpq by diesel
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \\
    apt-get update &&''', '''ARG DEBIAN_SNAPSHOT=20261120T000000Z
# a fixed snapshot keeps the apt libraries, and so the image digest, identical between builds
RUN sed -i -e "s|http://deb.debian.org/debian-security|http://snapshot.debian.org/archive/debian-security/${DEBIAN_SNAPSHOT}|" \\
    -e "s|http://deb.debian.org/debian$|http://snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT}|" /etc/apt/sources.list.d/debian.sources
# protoc is needed by crates/external_services/build.rs, libpq by diesel
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \\
    apt-get -o Acquire::Check-Valid-Until=false update &&''')
sub("docker/locker/Dockerfile", '''RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \\
    apt-get update &&''', '''ARG DEBIAN_SNAPSHOT=20261120T000000Z
# a fixed snapshot keeps the apt libraries, and so the image digest, identical between builds
RUN sed -i -e "s|http://deb.debian.org/debian-security|http://snapshot.debian.org/archive/debian-security/${DEBIAN_SNAPSHOT}|" \\
    -e "s|http://deb.debian.org/debian$|http://snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT}|" /etc/apt/sources.list.d/debian.sources
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \\
    apt-get -o Acquire::Check-Valid-Until=false update &&''')
print("ok")
