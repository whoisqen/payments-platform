# rust:1.92.0-bookworm (manifest list, arm64 and amd64)
FROM rust@sha256:e90e846de4124376164ddfbaab4b0774c7bdeef5e738866295e5a90a34a307a2 AS tools
ARG CHEF_VERSION=0.1.71
ARG SCCACHE_VERSION=0.10.0
ARG DEBIAN_SNAPSHOT=20261120T000000Z
# a fixed snapshot keeps the apt libraries, and so the image digest, identical between builds
RUN sed -i -e "s|http://deb.debian.org/debian-security|http://snapshot.debian.org/archive/debian-security/${DEBIAN_SNAPSHOT}|" \
    -e "s|http://deb.debian.org/debian$|http://snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT}|" /etc/apt/sources.list.d/debian.sources
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    apt-get -o Acquire::Check-Valid-Until=false update && apt-get install -y --no-install-recommends libpq-dev libssl-dev pkg-config
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    cargo install --locked cargo-chef --version "${CHEF_VERSION}" \
    && cargo install --locked sccache --version "${SCCACHE_VERSION}"

FROM tools AS chef
WORKDIR /src
COPY vendor/card-vault/ ./
RUN cargo chef prepare --recipe-path /recipe.json

FROM tools AS build
ARG SOURCE_DATE_EPOCH
ARG CARGO_PROFILE=release
ARG RUSTFLAGS="-C strip=symbols --remap-path-prefix=/src=/build --remap-path-prefix=/usr/local/cargo=/cargo"
ARG SCCACHE_BUCKET=""
ARG SCCACHE_REGION=""
# build.rs runs vergen, which must not fail when .git is absent from the context
ENV SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH} RUSTFLAGS=${RUSTFLAGS} CARGO_INCREMENTAL=0 VERGEN_IDEMPOTENT=true \
    RUSTC_WRAPPER=sccache SCCACHE_BUCKET=${SCCACHE_BUCKET} SCCACHE_REGION=${SCCACHE_REGION}
WORKDIR /src
COPY --from=chef /recipe.json /recipe.json
# the AWS credentials for the sccache bucket come from a build secret, never from ARG or ENV
RUN --mount=type=secret,id=aws,target=/root/.aws/credentials \
    --mount=type=cache,target=/usr/local/cargo/registry \
    cargo chef cook --locked --profile "${CARGO_PROFILE}" --features release --recipe-path /recipe.json
COPY vendor/card-vault/ ./
RUN --mount=type=secret,id=aws,target=/root/.aws/credentials \
    --mount=type=cache,target=/usr/local/cargo/registry \
    cargo build --locked --profile "${CARGO_PROFILE}" --features release --bin locker \
    && install -D "target/${CARGO_PROFILE}/locker" /out/locker
COPY docker/_common/collect-libs.sh /usr/local/bin/collect-libs.sh
RUN /usr/local/bin/collect-libs.sh /out/locker /out/rootfs

# distroless cc-debian12 nonroot (manifest list, arm64 and amd64)
FROM gcr.io/distroless/cc-debian12@sha256:9dac0a79194e45a7da0158a9c6da57b217585af0786db3845d1f0ec1a0dd182f AS runtime
ARG SOURCE_DATE_EPOCH
ARG SOURCE_URL=unknown
ARG REVISION=unknown
ARG CREATED=unknown
LABEL org.opencontainers.image.source="${SOURCE_URL}" \
      org.opencontainers.image.revision="${REVISION}" \
      org.opencontainers.image.created="${CREATED}"
WORKDIR /app
COPY --from=build --chmod=a=rX /out/rootfs/ /
COPY --from=build --chmod=0555 /out/locker /app/locker
COPY --from=build --chmod=a=rX /src/config/ /app/config/
USER 10001:10001
STOPSIGNAL SIGTERM
ENTRYPOINT ["/app/locker"]
