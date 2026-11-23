# dr-failover

Promotes the standby region's data stores when the Route 53 health check of the working region has failed for `alarm_evaluation_periods` minutes.
Alarm (us-east-1, where Route 53 publishes its metrics) -> SNS -> Lambda running `scripts/dr/failover.py --mode warm --auto` for every cell: fence what is reachable, `failover-global-cluster` for each Aurora global cluster, drop the standby region from the DynamoDB deny-write policy.
Route 53 moves the traffic by itself; this module moves the data. A DynamoDB lock record per cell and one concurrent run keep a second alarm from promoting twice.
Missing health check data never starts a failover. Test: `terraform init -backend=false && terraform test`.
