# hyperswitch-control-center v1.39.0 prebuilt upstream image (manifest list, arm64 and amd64); no source is vendored
FROM docker.juspay.io/juspaydotin/hyperswitch-control-center@sha256:19a4c9c15b89865798b9730445cd5a1e84820896d6383c3eed97ad6e61ce18b0 AS runtime
ARG SOURCE_URL=unknown
ARG REVISION=unknown
ARG CREATED=unknown
LABEL org.opencontainers.image.source="${SOURCE_URL}" \
      org.opencontainers.image.revision="${REVISION}" \
      org.opencontainers.image.created="${CREATED}"
# the upstream user is a named one; the platform runs every image as 10001
USER root
RUN chown -R 10001:10001 /usr/src/app
USER 10001:10001
STOPSIGNAL SIGTERM
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["/bin/bash", "-c", "npm run serve"]
