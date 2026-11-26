# docker/_common

Files shared by the service Dockerfiles. Docker has no include mechanism, so each Dockerfile copies `collect-libs.sh` from here and repeats the pinned stages.

- `collect-libs.sh`: shared libraries a Rust binary needs beyond distroless, copied from the snapshot-pinned build stage; it fails the build when `ldd` reports a library as `not found`.
- `build-args.env`: reproducible-build settings; the images workflow passes them as `--build-arg`. A change here rebuilds every image (`rebuild_all` in `tools/ci/image-paths.yaml`; test areas live apart in `tools/ci/areas.yaml`).
- `budgets.yaml`: image size budgets in MiB.
- `structure-test.yaml`: container-structure-test template; `${SERVICE}` is substituted by the workflow. A `docker/<service>/structure-test.yaml` replaces it, so it repeats these checks (router and scheduler add libssl, libcrypto, the CA bundle and `SSL_CERT_FILE`).
