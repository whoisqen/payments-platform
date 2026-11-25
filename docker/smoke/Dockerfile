# distroless python3-debian12 nonroot (manifest list, arm64 and amd64); the standard library only, no third-party package is installed
FROM gcr.io/distroless/python3-debian12@sha256:7d1042ce588ab97019fe95c24ffca7bc5a82ccdac572511d5e09bda4435c89c5 AS runtime
ARG SOURCE_DATE_EPOCH
ARG SOURCE_URL=unknown
ARG REVISION=unknown
ARG CREATED=unknown
LABEL org.opencontainers.image.source="${SOURCE_URL}" \
      org.opencontainers.image.revision="${REVISION}" \
      org.opencontainers.image.created="${CREATED}"
# only the smoke package: `python3 -m smoke.live` imports it from WORKDIR
COPY --chmod=a=rX tests/smoke/ /app/smoke/
WORKDIR /app
# the root filesystem is read-only in the Jobs: no bytecode is written
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PYTHONPATH=/app
USER 10001:10001
# the base entrypoint is python3; the Job passes its own arguments
CMD ["-m", "smoke.live"]
