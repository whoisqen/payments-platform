output "web_acl_arns" {
  value       = { for k, a in aws_wafv2_web_acl.this : k => a.arn }
  description = "Web ACL ARN by entry."
}

output "log_group_names" {
  value       = { for k, g in aws_cloudwatch_log_group.waf : k => g.name }
  description = "WAF log group by entry."
}

output "association" {
  value = var.scope == "CLOUDFRONT" ? {
    for k, a in aws_wafv2_web_acl.this : k => "set web_acl_id = <this ARN> on the aws_cloudfront_distribution of the ${k} entry"
    } : {
    for k, a in aws_wafv2_web_acl.this : k => "create an aws_wafv2_web_acl_association with resource_arn of the ALB or API Gateway stage of the ${k} entry"
  }
  description = "How to attach each ACL; the module does not own the distributions."
}
