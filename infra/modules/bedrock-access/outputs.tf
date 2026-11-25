output "review_role_arn" {
  value       = aws_iam_role.review.arn
  description = "Role the AI review workflow assumes; the owner sets it as the repository variable AI_REVIEW_ROLE_ARN."
}

output "admin_role_arn" {
  value       = try(aws_iam_role.admin[0].arn, null)
  description = "Role of the admin AI agent; null when admin_principal_arns is empty."
}

output "endpoint_id" {
  value       = aws_vpc_endpoint.runtime.id
  description = "ID of the bedrock-runtime interface endpoint."
}

output "endpoint_security_group_id" {
  value       = aws_security_group.endpoint.id
  description = "Security group of the endpoint."
}

output "invocation_log_bucket" {
  value       = try(aws_s3_bucket.invocation_logs[0].id, null)
  description = "Bucket of the invocation logs; null while logging is disabled."
}

output "guardrail_id" {
  value       = aws_bedrock_guardrail.this.guardrail_id
  description = "Guardrail id; callers pass it as guardrailIdentifier."
}

output "guardrail_arn" {
  value       = aws_bedrock_guardrail.this.guardrail_arn
  description = "Guardrail ARN."
}

output "guardrail_version" {
  value       = aws_bedrock_guardrail_version.this.version
  description = "Published guardrail version; callers pass it as guardrailVersion (the roles allow only this one)."
}

output "eu_only_scp_policy_json" {
  value = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "DenyBedrockInvokeOutsideEu"
      Effect   = "Deny"
      Action   = ["bedrock:Invoke*"]
      Resource = "*"
      Condition = {
        StringNotLike = { "aws:RequestedRegion" = [local.eu_regions_pattern] }
      }
    }]
  })
  description = "Service control policy document that denies bedrock:Invoke* outside EU regions; attach it from the organization stack (this module does not create it)."
}

output "budget_name" {
  value       = aws_budgets_budget.bedrock.name
  description = "Monthly Bedrock budget."
}
