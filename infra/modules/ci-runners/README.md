# ci-runners

Self-hosted GitHub Actions runners as persistent pools of Spot instances: one Auto Scaling group per kind of job, arm64, no Kubernetes.
Each instance installs the pinned runner at boot, registers itself through the GitHub App of its pool and runs as a systemd service; it is stateless and Spot or a new image replaces it.
CPU target tracking adds instances, scheduled actions keep `warm_size` instances during working hours, a busy instance is protected from scale-in.
Pools differ by what their role may do (cache write, image pull, plan roles); the untrusted pool has no role, own subnets and no access to the instance credentials.
Also: build cache bucket with KMS, GitHub App secrets (names only, values set by the owner), ECR push role for main and release branches.
Test: `terraform init -backend=false && terraform test`.
