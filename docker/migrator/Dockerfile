# rust:1.94.1-bookworm (manifest list, arm64 and amd64)
FROM rust@sha256:6ae102bdbf528294bc79ad6e1fae682f6f7c2a6e6621506ba959f9685b308a55 AS diesel
ARG DIESEL_VERSION=2.2.4
ARG DEBIAN_SNAPSHOT=20261120T000000Z
ARG SOURCE_DATE_EPOCH
ARG RUSTFLAGS="-C strip=symbols --remap-path-prefix=/usr/local/cargo=/cargo"
ENV SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH} RUSTFLAGS=${RUSTFLAGS} CARGO_INCREMENTAL=0
# a fixed snapshot keeps the apt libraries, and so the image digest, identical between builds
RUN sed -i -e "s|http://deb.debian.org/debian-security|http://snapshot.debian.org/archive/debian-security/${DEBIAN_SNAPSHOT}|" \
    -e "s|http://deb.debian.org/debian$|http://snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT}|" /etc/apt/sources.list.d/debian.sources
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    apt-get -o Acquire::Check-Valid-Until=false update && apt-get install -y --no-install-recommends libpq-dev pkg-config
# postgres only: no MySQL or SQLite client library reaches the image
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    cargo install --locked diesel_cli --version "${DIESEL_VERSION}" --no-default-features --features postgres --root /out

# debian:bookworm-slim (manifest list, arm64 and amd64)
FROM debian@sha256:734a72b3d6142a71993b4bc580ca01d8ca687f77a2c422d96a961d3376b179bc AS tools
# Only linux/arm64 (the platform of images.yml); the checksum below is of the arm64 artifact
ARG AWSCLI_VERSION=2.27.50
ARG AWSCLI_SHA256=bd8c0bf5e1df241d3a8a3fe3ac40bf0573236735fc6b5e6c86701b8a8c218eff
ARG DEBIAN_SNAPSHOT=20261120T000000Z
RUN sed -i -e "s|http://deb.debian.org/debian-security|http://snapshot.debian.org/archive/debian-security/${DEBIAN_SNAPSHOT}|" \
    -e "s|http://deb.debian.org/debian$|http://snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT}|" /etc/apt/sources.list.d/debian.sources
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    apt-get -o Acquire::Check-Valid-Until=false update \
    && apt-get install -y --no-install-recommends ca-certificates curl unzip postgresql-client-15 libpq5
WORKDIR /dl
# the download is verified against a pinned sha256 before it is used
RUN curl -fsSLo awscli.zip "https://awscli.amazonaws.com/awscli-exe-linux-aarch64-${AWSCLI_VERSION}.zip" \
    && echo "${AWSCLI_SHA256}  awscli.zip" >awscli.sha256 && sha256sum -c awscli.sha256 \
    && unzip -q awscli.zip \
    && ./aws/install --install-dir /out/aws-cli --bin-dir /out/aws-bin
COPY --from=diesel /out/bin/diesel /out/bin/diesel
COPY --chmod=0755 docker/_common/collect-libs.sh /usr/local/bin/collect-libs.sh
# The entrypoints are bash (the D3 snapshot script, the advisory lock of migrate.sh), so exactly the programs they call
# are copied onto distroless with their libraries; Debian's /usr/bin/psql is a perl wrapper, the real binary is taken.
RUN set -eu; \
    for b in /bin/bash /usr/bin/env /usr/bin/sha256sum /usr/bin/cut /usr/bin/sleep /usr/bin/wc /usr/bin/tail \
             /usr/bin/basename /usr/bin/dirname /usr/bin/find /usr/bin/mawk /usr/lib/postgresql/15/bin/psql; do \
      install -D -m 0555 "$b" "/out/bin/$(basename "$b")"; \
      collect-libs.sh "$b" /out/rootfs; \
    done; \
    collect-libs.sh /out/bin/diesel /out/rootfs; \
    ln -s mawk /out/bin/awk

# distroless cc-debian12 nonroot (manifest list, arm64 and amd64)
FROM gcr.io/distroless/cc-debian12@sha256:9dac0a79194e45a7da0158a9c6da57b217585af0786db3845d1f0ec1a0dd182f AS runtime
ARG SOURCE_DATE_EPOCH
ARG SOURCE_URL=unknown
ARG REVISION=unknown
ARG CREATED=unknown
LABEL org.opencontainers.image.source="${SOURCE_URL}" \
      org.opencontainers.image.revision="${REVISION}" \
      org.opencontainers.image.created="${CREATED}"
COPY --from=tools --chmod=a=rX /out/rootfs/ /
# /usr/bin, because every script starts with #!/usr/bin/env bash
COPY --from=tools /out/bin/ /usr/bin/
COPY --from=tools --chmod=a=rX /out/aws-cli/ /usr/local/aws-cli/
COPY --chmod=a=rX vendor/hyperswitch/migrations/ /opt/migrator/migrations/
COPY --chmod=0555 scripts/schema/pre-migration-snapshot.sh /opt/migrator/pre-migration-snapshot.sh
COPY --chmod=0555 docker/migrator/migrate.sh docker/migrator/snapshot.sh docker/migrator/backfill.sh /opt/migrator/
# no writes outside /tmp: the Job mounts an emptyDir there and sets the root filesystem read-only.
# verify-full needs the Amazon RDS CA bundle at PGSSLROOTCERT; the Job that runs the image provides that file.
ENV HOME=/tmp AWS_PAGER="" \
    PGSSLROOTCERT=/etc/ssl/rds/global-bundle.pem \
    PATH=/usr/local/aws-cli/v2/current/bin:/usr/bin
WORKDIR /tmp
# a run-to-completion Job: Kubernetes tracks it, so the image carries no Docker health check
HEALTHCHECK NONE
USER 10001:10001
ENTRYPOINT ["/opt/migrator/migrate.sh"]
