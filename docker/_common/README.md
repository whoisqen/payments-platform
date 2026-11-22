# docker/_common

Files shared by the service Dockerfiles. Docker has no include mechanism, so each Dockerfile copies `collect-libs.sh` from here and repeats the pinned stages.

- `collect-libs.sh`: shared libraries a Rust binary needs beyond distroless.
- `build-args.env`: reproducible-build settings; the images workflow passes them as `--build-arg`. A change here rebuilds every image (`tools/ci/image-paths.yaml`).
- `budgets.yaml`: image size budgets in MiB.
- `structure-test.yaml`: container-structure-test template; `${SERVICE}` is substituted by the workflow.
