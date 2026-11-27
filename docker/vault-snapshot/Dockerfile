# hashicorp/vault:2.0.4 (manifest list; same minor as appVersion of the vault chart 0.34.1)
FROM hashicorp/vault@sha256:5be49781ecf78bfe775c5309c6a4d9f4e9e040b6c885c99eb2b12fb69855e1a2 AS vault

# debian:bookworm-slim (manifest list, arm64 and amd64)
FROM debian@sha256:734a72b3d6142a71993b4bc580ca01d8ca687f77a2c422d96a961d3376b179bc AS fetch
# Only linux/arm64 (the platform of images.yml); the checksums below are of the arm64 artifacts
ARG AWSCLI_VERSION=2.27.50
ARG AWSCLI_SHA256=bd8c0bf5e1df241d3a8a3fe3ac40bf0573236735fc6b5e6c86701b8a8c218eff
ARG JQ_VERSION=1.7.1
ARG JQ_SHA256=4dd2d8a0661df0b22f1bb9a1f9830f06b6f3b8f7d91211a1ef5d7c4f06a8b4a5
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends ca-certificates curl unzip
WORKDIR /dl
# every download is verified against a pinned sha256 before it is used
RUN curl -fsSLo awscli.zip "https://awscli.amazonaws.com/awscli-exe-linux-aarch64-${AWSCLI_VERSION}.zip" \
    && echo "${AWSCLI_SHA256}  awscli.zip" >awscli.sha256 && sha256sum -c awscli.sha256 \
    && unzip -q awscli.zip \
    && ./aws/install --install-dir /out/aws-cli --bin-dir /out/bin \
    && curl -fsSLo /out/bin/jq "https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-linux-arm64" \
    && echo "${JQ_SHA256}  /out/bin/jq" >jq.sha256 && sha256sum -c jq.sha256 \
    && chmod 0555 /out/bin/jq

# distroless cc-debian12 nonroot (manifest list, arm64 and amd64)
FROM gcr.io/distroless/cc-debian12@sha256:9dac0a79194e45a7da0158a9c6da57b217585af0786db3845d1f0ec1a0dd182f AS runtime
ARG SOURCE_DATE_EPOCH
ARG SOURCE_URL=unknown
ARG REVISION=unknown
ARG CREATED=unknown
LABEL org.opencontainers.image.source="${SOURCE_URL}" \
      org.opencontainers.image.revision="${REVISION}" \
      org.opencontainers.image.created="${CREATED}"
COPY --from=vault --chmod=0555 /bin/vault /usr/local/bin/vault
COPY --from=fetch --chmod=a=rX /out/aws-cli/ /usr/local/aws-cli/
COPY --from=fetch --chmod=0555 /out/bin/jq /usr/local/bin/jq
# no writes outside /tmp: the Jobs mount an emptyDir there and set the root filesystem read-only
ENV HOME=/tmp \
    AWS_PAGER="" PATH=/usr/local/aws-cli/v2/current/bin:/usr/local/bin:/usr/bin:/bin
USER 10001:10001
