# Kafka CLI with the MSK IAM auth jar, for the kafka-topics Job (deploy/platform/kafka-topics): creates the event topics on MSK
# through IAM on port 9098. Multi-arch: the JVM and the Kafka tarball are architecture-independent.

# debian:bookworm-slim (manifest list, arm64 and amd64)
FROM debian@sha256:734a72b3d6142a71993b4bc580ca01d8ca687f77a2c422d96a961d3376b179bc AS fetch
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG KAFKA_VERSION=4.3.2
ARG SCALA_VERSION=2.13
ARG KAFKA_SHA512=C2063485F90312BBA795052DF3E49B8EEA337ADF97F1111B946C60771C7A2F088055D2CCC7221D72FE30BD6A3F7A58348F14E14240EADDFE60446EA1C033618B
ARG MSK_IAM_VERSION=2.4.0
ARG MSK_IAM_SHA256=b758405bd032d0aa3579eabe3fc3344da7003d723c4bb687767924450da7bbfd
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends ca-certificates curl
WORKDIR /dl
# every download is verified against a pinned checksum before it is used
RUN curl -fsSLo kafka.tgz "https://archive.apache.org/dist/kafka/${KAFKA_VERSION}/kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz" \
    && echo "$(echo "${KAFKA_SHA512}" | tr 'A-F' 'a-f')  kafka.tgz" >kafka.sha512 && sha512sum -c kafka.sha512 \
    && mkdir -p /out/kafka && tar -xzf kafka.tgz -C /out/kafka --strip-components=1 \
    && rm -rf /out/kafka/site-docs /out/kafka/bin/windows \
    && curl -fsSLo /out/kafka/libs/aws-msk-iam-auth.jar "https://github.com/aws/aws-msk-iam-auth/releases/download/v${MSK_IAM_VERSION}/aws-msk-iam-auth-${MSK_IAM_VERSION}-all.jar" \
    && echo "${MSK_IAM_SHA256}  /out/kafka/libs/aws-msk-iam-auth.jar" >iam.sha256 && sha256sum -c iam.sha256

# eclipse-temurin:21-jre-noble (manifest list, arm64 and amd64): a JRE with a POSIX shell, which the Kafka scripts need
FROM eclipse-temurin@sha256:54999a956a8bf8be9af0052790a6a832bf91a62fad3199fd194c3cc28057fc62 AS runtime
ARG SOURCE_URL=unknown
ARG REVISION=unknown
ARG CREATED=unknown
LABEL org.opencontainers.image.source="${SOURCE_URL}" \
      org.opencontainers.image.revision="${REVISION}" \
      org.opencontainers.image.created="${CREATED}"
COPY --from=fetch --chmod=a=rX /out/kafka/ /opt/kafka/
# no writes outside /tmp: the Job mounts an emptyDir there and sets the root filesystem read-only
ENV PATH=/opt/kafka/bin:/opt/java/openjdk/bin:/usr/bin:/bin HOME=/tmp LOG_DIR=/tmp/kafka-logs \
    KAFKA_HEAP_OPTS="-Xms64m -Xmx256m"
# a run-to-completion Job: Kubernetes tracks it, so the image carries no Docker health check
HEALTHCHECK NONE
USER 10001:10001
ENTRYPOINT ["kafka-topics.sh"]
