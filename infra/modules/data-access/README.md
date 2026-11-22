# data-access

Security groups of the data stores of one cell (or of the locker) and the Aurora DB subnet group; the data modules take their ids as inputs.
Each store gets one group with ingress on its port only from the node security groups of the listed clusters, or only from another store (Aurora admits only its RDS Proxy, which may open connections to Aurora and nowhere else).
Recovery regions use it with empty client lists, so nothing can connect before the switch.
Required: `region`, `environment`, `component`, `vpc_id`, `data_subnet_ids`, `stores`, `tags`.
Test: `terraform init -backend=false && terraform test` (mock provider).
