# log-retention

`check_log_retention.py` fails when an `aws_cloudwatch_log_group` under `infra/` has no `retention_in_days` (or 0), a module with an `aws_lambda_function` declares no `/aws/lambda/` log group of its own, or an `aws_s3_bucket` whose name has `log` in it has no lifecycle expiration.

Run: `python3 infra/tests/log-retention/check_log_retention.py`, tests: `python3 -m unittest discover -s infra/tests/log-retention`.
