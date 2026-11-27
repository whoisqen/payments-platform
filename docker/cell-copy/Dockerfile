# The cell-copy Lambda function (services/cell-copy) of infra/modules/cell-migration: arm64 only, like the function.

# python:3.12-slim-bookworm on the build platform: downloads the arm64 wheels by hash, so no emulation is needed
FROM --platform=$BUILDPLATFORM python@sha256:44cf1793efa7c7a476bb0f2cff81443f4a072c90c1cb127e2924933daa3e8c64 AS deps
COPY docker/cell-copy/requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir --require-hashes --only-binary=:all: --platform manylinux2014_aarch64 \
      --implementation cp --python-version 3.12 --target /out -r /tmp/requirements.txt

# public.ecr.aws/lambda/python:3.12 (manifest list, arm64 and amd64)
FROM public.ecr.aws/lambda/python@sha256:ad2f55fe2cf91a997bc986410cab85a41b7c7bae65ba881e69173a76d022133e
ARG SOURCE_URL=unknown
ARG REVISION=unknown
ARG CREATED=unknown
LABEL org.opencontainers.image.source="${SOURCE_URL}" \
      org.opencontainers.image.revision="${REVISION}" \
      org.opencontainers.image.created="${CREATED}"
COPY --from=deps --chmod=a=rX /out/ ${LAMBDA_TASK_ROOT}/
COPY --chmod=0444 services/cell-copy/app.py ${LAMBDA_TASK_ROOT}/app.py
# a Lambda function: the Lambda service checks it, so the image carries no Docker health check
HEALTHCHECK NONE
USER 10001:10001
CMD ["app.handler"]
