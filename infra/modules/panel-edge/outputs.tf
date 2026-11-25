output "fqdns" {
  value       = local.fqdns
  description = "Public host name by entry."
}

output "certificate_arns" {
  value       = { for k, v in aws_acm_certificate_validation.this : k => v.certificate_arn }
  description = "Validated us-east-1 ACM certificate ARN by entry."
}

output "distribution_ids" {
  value       = { for k, d in aws_cloudfront_distribution.this : k => d.id }
  description = "CloudFront distribution id by entry; empty until the second step."
}

output "distribution_arns" {
  value       = { for k, d in aws_cloudfront_distribution.this : k => d.arn }
  description = "CloudFront distribution ARN by entry; empty until the second step."
}

output "distribution_domain_names" {
  value       = { for k, d in aws_cloudfront_distribution.this : k => d.domain_name }
  description = "cloudfront.net name by entry; empty until the second step."
}

output "vpc_origin_id" {
  value       = one(aws_cloudfront_vpc_origin.gateway[*].id)
  description = "Id of the VPC origin to the internal NLB; null until the second step."
}

output "access_log_destination" {
  value       = var.log_bucket_arn != null ? var.log_bucket_arn : one(aws_cloudwatch_log_group.access[*].name)
  description = "S3 bucket ARN or CloudWatch log group name that receives the access logs."
}
