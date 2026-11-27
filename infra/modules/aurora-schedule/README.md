# aurora-schedule

Stops the dev Aurora clusters outside the working window and starts them again (section 12: 60 of 168 hours) with EventBridge Scheduler universal targets `rds:stopDBCluster` and `rds:startDBCluster`.
AWS stops a cluster of a global database only when it is the only cluster, so this runs in dev, which has no recovery-region secondaries; stage keeps them and is rejected.
The scheduler role may only stop and start the listed clusters. The `env-up` workflow starts them outside the window; a stopped cluster starts by itself after seven days.
Test: `terraform init -backend=false && terraform test` (mock provider).
