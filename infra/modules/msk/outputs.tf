output "cluster_arn" {
  description = "ARN of the MSK cluster."
  value       = aws_msk_cluster.this.arn
}

output "cluster_name" {
  description = "Name of the MSK cluster."
  value       = aws_msk_cluster.this.cluster_name
}

output "bootstrap_brokers_sasl_iam" {
  description = "IAM-authenticated TLS bootstrap string."
  value       = aws_msk_cluster.this.bootstrap_brokers_sasl_iam
}

output "sink_role_arn" {
  description = "Role of the S3 sink connector."
  value       = aws_iam_role.sink.arn
}

output "sink_bucket_policy_statements" {
  description = "Statements for the s3-backup input bucket_policy_statements: the sink writes only under its prefix."
  value = [
    {
      Sid       = "MskS3SinkWrite"
      Effect    = "Allow"
      Principal = { AWS = aws_iam_role.sink.arn }
      Action    = ["s3:PutObject", "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"]
      Resource  = [local.sink_prefixes]
    },
    {
      Sid       = "MskS3SinkList"
      Effect    = "Allow"
      Principal = { AWS = aws_iam_role.sink.arn }
      Action    = ["s3:ListBucket", "s3:GetBucketLocation"]
      Resource  = [var.sink_bucket_arn]
    },
  ]
}

output "producer_policy_arn" {
  description = "Managed policy that gives a producer role IAM auth and write access to every topic of the cluster."
  value       = aws_iam_policy.producer.arn
}

output "client_settings" {
  description = "Producer settings: bootstrap string, port and the SASL setup of MSK IAM auth for librdkafka (OAUTHBEARER with an MSK IAM token)."
  value = {
    bootstrap_brokers = aws_msk_cluster.this.bootstrap_brokers_sasl_iam
    port              = 9098
    security_protocol = "SASL_SSL"
    sasl_mechanism    = "OAUTHBEARER"
  }
}
