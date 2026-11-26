# docker

One Dockerfile per service (`docker/<service>/Dockerfile`), `budgets.yaml` with image size budgets, container-structure-test.

Kafka TLS (router, scheduler): `rdkafka` is built with the `ssl` feature and links the system libssl and libcrypto, which `collect-libs.sh` copies from the snapshot-pinned build stage. librdkafka verifies the MSK certificates through OpenSSL's default paths under `/usr/lib/ssl`, which distroless does not have, so the runtime stage sets `SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt` (the bundle of the digest-pinned base). The drainer does not link rdkafka.

## Rootless builds

Images are built by BuildKit running rootless in pods of a build cluster; no runner has a Docker daemon, `docker.sock`, a privileged container or a hostPath. The runner holds only the buildx client.

- Driver: buildx `kubernetes` (`.github/actions/setup-buildkit`, used by `images.yml` and `nightly.yml`). One Deployment `buildkit-<run>-<attempt>-<service>` with one `moby/buildkit:<tag>-rootless` pod per job; `setup-buildx-action` removes it in its post step. The runner reaches it through the Kubernetes API (`pods/exec`), so no port, Service or certificate is exposed.
- Why not the `remote` driver: a shared buildkitd needs a Service reachable from the stateless runners, a client certificate on each of them and cleanup of one daemon shared by jobs of different branches. The `kubernetes` driver gets identity and isolation from the runner identity and the Kubernetes RBAC, and a runner that is replaced leaves nothing to rejoin.
- Pin: `tools/ci/buildkit/buildkit.env` holds `BUILDKIT_IMAGE=<repo>:<tag>-rootless@sha256:<digest>`; Renovate bumps it (`renovate.json5`). The digest is `REPLACE_BUILDKIT_DIGEST` until it is filled; `tools/ci/buildkit/buildkit_pin_check.py` warns in `make lint-docker` and fails (`--strict`) in the workflows, so no build runs on an unpinned image.
- Build command, `rewrite-timestamp`, `SOURCE_DATE_EPOCH`, registry cache and digest reuse are unchanged, so the same inputs give the same digest and the nightly `digest_compare` still applies. Layers are diffs, so the snapshotter does not change the digest.
- Tests and scans read the image from the registry (`crane pull` plus `container-structure-test --driver tar`, `trivy --image-src remote`, `syft registry:`); nothing is loaded into a daemon.

### Settings the owner provides

Repository variables (the build jobs are skipped while `BUILDKIT_NAMESPACE` is empty): `BUILDKIT_NAMESPACE`, `BUILDKIT_NODE_SELECTOR` (default `kubernetes.io/arch=arm64,pay.io/pool=ci-build`), `BUILDKIT_EKS_CLUSTER` (empty when the runner runs in the build cluster itself).

In the build cluster (`deploy/platform/ci-build/`, not written by this change):

- Namespace for the builders, dedicated; no other workload in it. Pod Security: rootless pods are not privileged but BuildKit needs `seccompProfile: Unconfined` (set by the driver with `rootless=true`, plus the AppArmor annotation and `--oci-worker-no-process-sandbox`), which the `baseline` level forbids, so the namespace needs `pod-security.kubernetes.io/enforce: privileged`, or a Kyverno exception limited to this namespace and the `moby/buildkit` image by digest.
- Node pool for the label of `BUILDKIT_NODE_SELECTOR`, arm64, taint matching a toleration if it is dedicated; nodes need user namespaces (kernel 5.11+, `kernel.unprivileged_userns_clone` or equivalent allowed) and egress to ECR, snapshot.debian.org, crates.io and the sccache S3 endpoint.
- Identity of the runner: an EKS access entry (or the in-cluster ServiceAccount) bound to a Role in that namespace only: `deployments` get, list, watch, create, update, patch, delete; `pods` get, list, watch; `pods/exec` create; `configmaps` get, list, watch, create, update, delete (buildkitd config). No ClusterRole. For a runner outside the cluster, the runner instance role also needs `eks:DescribeCluster`.
- A sweep of Deployments older than two hours in the namespace, for builders orphaned by a killed runner.
- Quota: a builder requests 8 CPU and 16 GiB (limit 24 GiB memory); size the namespace quota for the matrix (6 services).

### Limits of rootless

- The root of a `RUN` step is root of a user namespace, mapped to an unprivileged user of the pod. `apt-get`, `chown` to 10001, `useradd`, file capabilities inside the image are fine (the builder user has a 65536 uid range). Nothing that needs the real root works: `RUN --security=insecure`, `mknod` of real devices, `mount`, loading kernel modules, `sysctl`, access to the host network namespace.
- `--mount=type=cache` lives in the pod (emptyDir) and is lost with it; only the registry cache (`mode=max`) and the sccache bucket carry across jobs. A first build is slower than on the old persistent daemon.
- Snapshotter: `overlayfs` in a user namespace needs kernel 5.11 or newer; otherwise BuildKit falls back to `native`, which copies every layer and needs more disk and time. Check the choice in the builder log (`docker buildx inspect --bootstrap`).
- The build secret (`--secret id=aws`) and the registry credentials travel over the buildx session to the pod and are never written to an image layer or a volume.

### Dockerfile audit

Every Dockerfile runs as root only inside the build user namespace and has no step that needs real root:

- `router`, `drainer`, `scheduler`, `locker` (`tools`, `build` stages): `apt-get install` (also needs the `_apt` sandbox user, covered by the uid range; set `APT::Sandbox::User "root"` if a node refuses), `cargo install`, `cargo build`, a `--mount=type=secret` at `/root/.aws/credentials` and `--mount=type=cache` mounts. `collect-libs.sh` uses `ldd`, `grep`, `awk`, `cp`, `mkdir` only.
- `vault-snapshot` (`fetch` stage): `apt-get install`, `curl` with a pinned sha256, `unzip`, the AWS CLI installer into `/out`.
- `control-center`: `USER root` then `chown -R 10001:10001 /usr/src/app`; this needs the uid 10001 inside the user namespace map (it is within the 65536 range) and `CAP_CHOWN` of the namespace, which rootless BuildKit has. It is the only step that changes ownership; if a builder refuses it, use `COPY --chown=10001:10001` from the upstream stage instead.
- No Dockerfile uses `--security=insecure`, `mknod`, `mount`, `sysctl`, `setcap` or `chroot`. The final stages are distroless with `USER 10001:10001`.
