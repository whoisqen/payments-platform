# ci-runners

Self-hosted GitHub Actions runners as persistent pools of Spot instances: one Auto Scaling group per kind of job, arm64, no Kubernetes, IMDSv2 with one hop.
A trusted instance installs the pinned runner, registers through the GitHub App of its pool and runs as a systemd service; CPU target tracking and `warm_size` schedules size the pools, a busy instance is protected from scale-in.
Untrusted pools (pull requests) never hold the App key: a launch lifecycle hook triggers the `<prefix>-ci-jit-config` Lambda, the only reader of the key (secret policy), which stores a one-time JIT runner config with fixed labels as a SecureString `/<prefix>/ci/jit/<pool>/<instance-id>`. The function runs with X-Ray tracing, its environment and logs are encrypted with customer-managed keys, and lifecycle events it fails to handle go to the `<prefix>-ci-jit-config-dlq` queue.
The instance reads and deletes it, runs one job and powers off (terminate); no config means ABANDON. It has no docker, its runner user cannot reach IMDS, its role cannot read secrets or assume roles.
Untrusted pools need `untrusted_subnet_ids` (egress only through the Network Firewall allowlist) and `endpoint_security_group_id`; their security group allows HTTPS to public addresses and the interface endpoints only.
Also: build cache bucket with KMS, GitHub App secrets (names only, values set by the owner), ECR push role for main and release branches.
Test: `terraform init -backend=false && terraform test`.
