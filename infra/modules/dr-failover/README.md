# dr-failover

Promotes the standby region's data stores when the Route 53 health check of the working region has failed for `alarm_evaluation_periods` minutes.
Alarm (us-east-1, where Route 53 publishes its metrics) -> SNS -> Lambda running `scripts/dr/failover.py --auto` for every cell: fence what is reachable, `failover-global-cluster` for each Aurora global cluster, drop the standby region from the DynamoDB deny-write policy.
Route 53 moves the traffic by itself; this module moves the data. A DynamoDB lock record per cell and one concurrent run keep a second alarm from promoting twice.
The trigger topic is encrypted with a customer managed key (`alias/<name>-sns`, rotation on) whose policy lets `cloudwatch.amazonaws.com` use `kms:Decrypt` and `kms:GenerateDataKey*` for this account's alarm; CloudWatch alarms cannot publish to a topic encrypted with the AWS managed key `alias/aws/sns`.
`sns_kms_key_arn` uses an existing key instead; that key's policy must already grant CloudWatch, the module does not change it.
Missing health check data never starts a failover. Test: `terraform init -backend=false && terraform test`.
