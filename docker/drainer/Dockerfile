# rust:1.94.1-bookworm (manifest list, arm64 and amd64)
FROM rust@sha256:6ae102bdbf528294bc79ad6e1fae682f6f7c2a6e6621506ba959f9685b308a55 AS tools
ARG CHEF_VERSION=0.1.71
ARG SCCACHE_VERSION=0.10.0
ARG DEBIAN_SNAPSHOT=20261120T000000Z
# a fixed snapshot keeps the apt libraries, and so the image digest, identical between builds
RUN sed -i -e "s|http://deb.debian.org/debian-security|http://snapshot.debian.org/archive/debian-security/${DEBIAN_SNAPSHOT}|" \
    -e "s|http://deb.debian.org/debian$|http://snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT}|" /etc/apt/sources.list.d/debian.sources
# protoc is needed by crates/external_services/build.rs, libpq by diesel
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    apt-get -o Acquire::Check-Valid-Until=false update && apt-get install -y --no-install-recommends libpq-dev libssl-dev pkg-config protobuf-compiler
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    cargo install --locked cargo-chef --version "${CHEF_VERSION}" \
    && cargo install --locked sccache --version "${SCCACHE_VERSION}"

FROM tools AS chef
WORKDIR /src
COPY vendor/hyperswitch/ ./
RUN cargo chef prepare --recipe-path /recipe.json

FROM tools AS build
ARG SOURCE_DATE_EPOCH
ARG CARGO_PROFILE=release
ARG RUSTFLAGS="-C strip=symbols --remap-path-prefix=/src=/build --remap-path-prefix=/usr/local/cargo=/cargo"
ARG SCCACHE_BUCKET=""
ARG SCCACHE_REGION=""
ENV SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH} RUSTFLAGS=${RUSTFLAGS} CARGO_INCREMENTAL=0 \
    RUSTC_WRAPPER=sccache SCCACHE_BUCKET=${SCCACHE_BUCKET} SCCACHE_REGION=${SCCACHE_REGION}
WORKDIR /src
COPY --from=chef /recipe.json /recipe.json
# the AWS credentials for the sccache bucket come from a build secret, never from ARG or ENV
RUN --mount=type=secret,id=aws,target=/root/.aws/credentials \
    --mount=type=cache,target=/usr/local/cargo/registry \
    cargo chef cook --locked --profile "${CARGO_PROFILE}" --features release --features v1 --recipe-path /recipe.json
COPY vendor/hyperswitch/ ./
RUN --mount=type=secret,id=aws,target=/root/.aws/credentials \
    --mount=type=cache,target=/usr/local/cargo/registry \
    cargo build --locked --profile "${CARGO_PROFILE}" --features release --features v1 \
    && install -D "target/${CARGO_PROFILE}/drainer" /out/drainer
COPY docker/_common/collect-libs.sh /usr/local/bin/collect-libs.sh
RUN /usr/local/bin/collect-libs.sh /out/drainer /out/rootfs

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
COPY --from=build --chmod=0555 /out/drainer /app/drainer
COPY --from=build --chmod=a=rX /src/config/deployments/ /app/config/deployments/
COPY --from=build --chmod=a=rX /src/config/development.toml /app/config/development.toml
USER 10001:10001
STOPSIGNAL SIGTERM
ENTRYPOINT ["/app/drainer"]
