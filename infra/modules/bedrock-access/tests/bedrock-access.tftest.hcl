mock_provider "aws" {
  mock_resource "aws_bedrock_guardrail" {
    defaults = {
      guardrail_arn = "arn:aws:bedrock:eu-central-1:222222222222:guardrail/abc123xyz"
      guardrail_id  = "abc123xyz"
      version       = "DRAFT"
    }
  }
  mock_resource "aws_bedrock_guardrail_version" {
    defaults = {
      version = "1"
    }
  }
}

variables {
  name_prefix              = "pay"
  account_id               = "222222222222"
  region                   = "eu-central-1"
  inference_profile_id     = "eu.vendor.model-v1:0"
  profile_regions          = ["eu-central-1", "eu-west-1", "eu-north-1"]
  review_role_name         = "pay-shared-gha-ai-review"
  github_repository        = "acme/payments"
  github_oidc_provider_arn = "arn:aws:iam::222222222222:oidc-provider/token.actions.githubusercontent.com"
  admin_principal_arns     = ["arn:aws:iam::222222222222:role/aws-reserved/sso.amazonaws.com/*/AWSReservedSSO_BedrockAdmin_*"]
  admin_allowed_model_arns = ["arn:aws:bedrock:eu-central-1::foundation-model/vendor.model-v1:0"]
  admin_log_group_names    = ["/pay/central/app", "/pay/central/audit"]
  cde_account_ids          = ["333333333333"]
  budget_subscriber_emails = ["platform@example.com"]
  vpc_id                   = "vpc-0123456789abcdef0"
  subnet_ids               = ["subnet-aaa", "subnet-bbb"]
  endpoint_allowed_cidrs   = ["10.20.0.0/16"]
  tags = {
    team          = "platform"
    owner         = "platform@example.com"
    "pci-scope"   = "out-of-scope"
    "data-class"  = "internal"
    "backup-tier" = "none"
  }
}

run "review_role_is_pinned_and_scoped" {
  command = apply

  assert {
    condition = (jsondecode(aws_iam_role.review.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:acme/payments:environment:ai-review"
    && jsondecode(aws_iam_role.review.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:aud"] == "sts.amazonaws.com")
    error_message = "trust must pin sub to the GitHub environment of the repository and aud to sts"
  }

  assert {
    condition     = aws_iam_role.review.name == "pay-shared-gha-ai-review" && aws_iam_role.review.max_session_duration == 3600
    error_message = "name from configuration, one hour session"
  }

  assert {
    condition     = alltrue([for s in jsondecode(aws_iam_role_policy.review.policy).Statement : s.Effect == "Allow" && !strcontains(jsonencode(s.Resource), "*") && !contains(s.Action, "bedrock:*")])
    error_message = "no wildcard resource or action for invoke"
  }

  assert {
    condition     = length(jsondecode(aws_iam_role_policy.review.policy).Statement[1].Resource) == 3 && contains(jsondecode(aws_iam_role_policy.review.policy).Statement[1].Resource, "arn:aws:bedrock:eu-west-1::foundation-model/vendor.model-v1:0")
    error_message = "one foundation-model ARN per profile region, geo prefix stripped"
  }
}

run "admin_role_is_read_only" {
  command = apply

  assert {
    condition     = !contains(keys(jsondecode(aws_iam_role.admin[0].assume_role_policy).Statement[0].Condition), "Bool")
    error_message = "MFA key is absent from Identity Center sessions, so it is off by default"
  }

  assert {
    condition     = jsondecode(aws_iam_role.admin[0].assume_role_policy).Statement[0].Condition.ArnLike["aws:PrincipalArn"][0] == var.admin_principal_arns[0]
    error_message = "admin trust is limited to the admin principals"
  }

  assert {
    condition     = alltrue([for s in jsondecode(aws_iam_role_policy.admin[0].policy).Statement : s.Sid != "InvokeAllowedModels" || !strcontains(jsonencode(s.Resource), "*")])
    error_message = "invoke resources are the listed models"
  }

  assert {
    condition = (anytrue([for s in jsondecode(aws_iam_role_policy.admin[0].policy).Statement : s.Sid == "DenyWrites" && contains(s.Action, "logs:Put*") && contains(s.Action, "cloudwatch:Put*") && contains(s.Action, "bedrock:Delete*")])
      && anytrue([for s in jsondecode(aws_iam_role_policy.admin[0].policy).Statement : s.Sid == "DenySecretsAndKeys" && contains(s.Action, "kms:*") && contains(s.Action, "secretsmanager:*")])
    && anytrue([for s in jsondecode(aws_iam_role_policy.admin[0].policy).Statement : s.Sid == "DenyAnythingElse" && s.Effect == "Deny"]))
    error_message = "explicit deny on writes, secrets and keys, and on everything outside the allow list"
  }

  assert {
    condition     = anytrue([for s in jsondecode(aws_iam_role_policy.admin[0].policy).Statement : s.Sid == "DenyCdeLogGroups" && s.Resource == ["arn:aws:logs:*:333333333333:*"]])
    error_message = "CDE account logs are denied by default"
  }

  assert {
    condition = anytrue([for s in jsondecode(aws_iam_role_policy.admin[0].policy).Statement :
    s.Sid == "DenyCdeMetricsAndOam" && contains(s.Action, "cloudwatch:GetMetricData") && contains(s.Action, "oam:*") && s.Condition.StringEquals["aws:ResourceAccount"] == ["333333333333"]])
    error_message = "metrics and OAM of CDE accounts are denied by aws:ResourceAccount"
  }

  assert {
    condition = anytrue([for s in jsondecode(aws_iam_role_policy.admin[0].policy).Statement :
    s.Sid == "DenyInvokeOutsideEndpoint" && s.Effect == "Deny" && contains(s.Action, "bedrock:Invoke*") && s.Condition.StringNotEquals["aws:SourceVpce"] == aws_vpc_endpoint.runtime.id])
    error_message = "admin invoke is refused outside the endpoint"
  }

  assert {
    condition     = !anytrue([for s in jsondecode(aws_iam_role_policy.admin[0].policy).Statement : s.Effect == "Allow" && anytrue([for a in flatten([s.Action]) : startswith(a, "secretsmanager:") || startswith(a, "kms:")])])
    error_message = "no allow on secrets or keys"
  }
}

run "cde_logs_can_be_allowed_by_variable" {
  command = apply

  variables {
    cde_logs_allowed = true
  }

  assert {
    condition     = !anytrue([for s in jsondecode(aws_iam_role_policy.admin[0].policy).Statement : s.Sid == "DenyCdeLogGroups" || s.Sid == "DenyCdeMetricsAndOam"])
    error_message = "the CDE deny is lifted only by the variable"
  }
}

run "no_admin_role_without_principals" {
  command = apply

  variables {
    admin_principal_arns = []
  }

  assert {
    condition     = length(aws_iam_role.admin) == 0 && length(jsondecode(aws_vpc_endpoint.runtime.policy).Statement) == 1
    error_message = "no admin role and no admin statement in the endpoint policy"
  }
}

run "endpoint_is_private_and_restricted" {
  command = apply

  assert {
    condition     = aws_vpc_endpoint.runtime.private_dns_enabled && aws_vpc_endpoint.runtime.vpc_endpoint_type == "Interface" && aws_vpc_endpoint.runtime.service_name == "com.amazonaws.eu-central-1.bedrock-runtime"
    error_message = "interface endpoint with private DNS"
  }

  assert {
    condition     = alltrue([for s in jsondecode(aws_vpc_endpoint.runtime.policy).Statement : s.Effect == "Allow" && !strcontains(jsonencode(s.Resource), "*") && !strcontains(jsonencode(s.Principal), "*")])
    error_message = "endpoint policy names its principals and models"
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.https) == 1 && aws_vpc_security_group_ingress_rule.https["10.20.0.0/16"].from_port == 443
    error_message = "443 from the given CIDRs only"
  }
}

run "invocation_logging_is_off_by_default" {
  command = apply

  assert {
    condition     = length(aws_bedrock_model_invocation_logging_configuration.this) == 0 && length(aws_s3_bucket.invocation_logs) == 0
    error_message = "no prompt bodies are delivered by default"
  }
}

run "invocation_logging_with_kms_and_30_days" {
  command = apply

  variables {
    invocation_logging_enabled       = true
    kms_key_arn                      = "arn:aws:kms:eu-central-1:222222222222:key/mrk-shared"
    invocation_log_audit_role_arn    = "arn:aws:iam::222222222222:role/aws-reserved/sso.amazonaws.com/*/AWSReservedSSO_Audit_*"
    invocation_log_access_log_bucket = "pay-access-logs"
  }

  assert {
    condition     = [for r in aws_s3_bucket_lifecycle_configuration.invocation_logs[0].rule : r.expiration[0].days][0] == 30 && [for r in aws_s3_bucket_server_side_encryption_configuration.invocation_logs[0].rule : r.apply_server_side_encryption_by_default[0].sse_algorithm][0] == "aws:kms"
    error_message = "30 day expiry and KMS encryption"
  }
}

run "wildcard_model_is_rejected" {
  command = plan

  variables {
    admin_allowed_model_arns = ["arn:aws:bedrock:*::foundation-model/*"]
  }

  expect_failures = [var.admin_allowed_model_arns]
}

run "open_cidr_is_rejected" {
  command = plan

  variables {
    endpoint_allowed_cidrs = ["0.0.0.0/0"]
  }

  expect_failures = [var.endpoint_allowed_cidrs]
}

run "review_environment_is_configurable" {
  command = apply

  variables {
    review_github_environment = "review-prod"
  }

  assert {
    condition     = jsondecode(aws_iam_role.review.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:acme/payments:environment:review-prod"
    error_message = "sub follows the environment variable"
  }
}

run "admin_trust_uses_principal_tag_and_optional_mfa" {
  command = apply

  variables {
    admin_require_mfa   = true
    admin_principal_tag = { key = "team", value = "platform" }
  }

  assert {
    condition = (jsondecode(aws_iam_role.admin[0].assume_role_policy).Statement[0].Condition.StringEquals["aws:PrincipalTag/team"] == "platform"
      && jsondecode(aws_iam_role.admin[0].assume_role_policy).Statement[0].Condition.Bool["aws:MultiFactorAuthPresent"] == "true"
    && !strcontains(aws_iam_role.admin[0].assume_role_policy, "RequestTag"))
    error_message = "principal tag, no request tag, MFA only when asked"
  }
}

run "bare_role_admin_principal_is_rejected" {
  command = plan

  variables {
    admin_principal_arns = ["arn:aws:iam::222222222222:role/*"]
  }

  expect_failures = [var.admin_principal_arns]
}

run "plain_role_admin_principal_is_rejected" {
  command = plan

  variables {
    admin_principal_arns = ["arn:aws:iam::222222222222:role/ops-admin"]
  }

  expect_failures = [var.admin_principal_arns]
}

run "guardrail_blocks_card_data_and_keys" {
  command = apply

  assert {
    condition = (toset([for e in aws_bedrock_guardrail.this.sensitive_information_policy_config[0].pii_entities_config : e.type]) == toset(["CREDIT_DEBIT_CARD_NUMBER", "CREDIT_DEBIT_CARD_CVV", "AWS_ACCESS_KEY"])
    && alltrue([for e in aws_bedrock_guardrail.this.sensitive_information_policy_config[0].pii_entities_config : e.action == "BLOCK"]))
    error_message = "card number, CVV and AWS keys are blocked"
  }

  assert {
    condition     = one([for f in aws_bedrock_guardrail.this.content_policy_config[0].filters_config : f.type]) == "PROMPT_ATTACK" && one([for f in aws_bedrock_guardrail.this.content_policy_config[0].filters_config : f.input_strength]) == "HIGH"
    error_message = "prompt-attack filter at HIGH"
  }

  assert {
    condition     = aws_bedrock_guardrail_version.this.guardrail_arn == aws_bedrock_guardrail.this.guardrail_arn
    error_message = "a version of the guardrail is published"
  }
}

run "invoke_allows_require_the_guardrail" {
  command = apply

  assert {
    condition = alltrue([for s in jsondecode(aws_iam_role_policy.review.policy).Statement :
    contains(keys(s.Condition.StringEquals), "bedrock:GuardrailIdentifier")])
    error_message = "every review invoke allow carries the guardrail condition"
  }

  assert {
    condition = anytrue([for s in jsondecode(aws_iam_role_policy.admin[0].policy).Statement :
    s.Sid == "InvokeAllowedModels" && contains(keys(s.Condition.StringEquals), "bedrock:GuardrailIdentifier")])
    error_message = "admin invoke allow carries the guardrail condition"
  }
}

run "cde_accounts_are_required" {
  command = plan

  variables {
    cde_account_ids = []
  }

  expect_failures = [var.cde_account_ids]
}

run "non_eu_profile_is_rejected" {
  command = plan

  variables {
    inference_profile_id = "us.vendor.model-v1:0"
  }

  expect_failures = [var.inference_profile_id]
}

run "non_eu_profile_region_is_rejected" {
  command = plan

  variables {
    profile_regions = ["eu-central-1", "us-east-1"]
  }

  expect_failures = [var.profile_regions]
}

run "non_eu_admin_model_is_rejected" {
  command = plan

  variables {
    admin_allowed_model_arns = ["arn:aws:bedrock:us-east-1::foundation-model/vendor.model-v1:0"]
  }

  expect_failures = [var.admin_allowed_model_arns]
}

run "scp_document_denies_invoke_outside_eu" {
  command = apply

  assert {
    condition = (jsondecode(output.eu_only_scp_policy_json).Statement[0].Effect == "Deny"
      && jsondecode(output.eu_only_scp_policy_json).Statement[0].Action == ["bedrock:Invoke*"]
    && jsondecode(output.eu_only_scp_policy_json).Statement[0].Condition.StringNotLike["aws:RequestedRegion"] == ["eu-*"])
    error_message = "SCP document denies invoke outside eu-*"
  }
}

run "invocation_log_bucket_is_locked_down" {
  command = apply

  variables {
    invocation_logging_enabled       = true
    kms_key_arn                      = "arn:aws:kms:eu-central-1:222222222222:key/mrk-shared"
    invocation_log_audit_role_arn    = "arn:aws:iam::222222222222:role/aws-reserved/sso.amazonaws.com/*/AWSReservedSSO_Audit_*"
    invocation_log_access_log_bucket = "pay-access-logs"
    invocation_log_object_lock       = { mode = "COMPLIANCE", days = 30 }
  }

  assert {
    condition     = aws_s3_bucket.invocation_logs[0].tags["pci-scope"] == "connected" && aws_s3_bucket.invocation_logs[0].object_lock_enabled
    error_message = "bucket is tagged connected and has Object Lock"
  }

  assert {
    condition = anytrue([for s in jsondecode(aws_s3_bucket_policy.invocation_logs[0].policy).Statement :
    s.Sid == "DenyReadExceptAuditRole" && s.Effect == "Deny" && contains(s.Action, "s3:GetObject") && s.Condition.ArnNotLike["aws:PrincipalArn"] == var.invocation_log_audit_role_arn])
    error_message = "GetObject is denied to everyone but the audit role"
  }

  assert {
    condition     = aws_s3_bucket_logging.invocation_logs[0].target_bucket == "pay-access-logs"
    error_message = "server access logging is on"
  }

  assert {
    condition     = one([for r in aws_s3_bucket_object_lock_configuration.invocation_logs[0].rule : one(r.default_retention).mode]) == "COMPLIANCE"
    error_message = "default retention mode"
  }
}

run "invocation_logging_needs_audit_role" {
  command = plan

  variables {
    invocation_logging_enabled = true
    kms_key_arn                = "arn:aws:kms:eu-central-1:222222222222:key/mrk-shared"
  }

  expect_failures = [aws_s3_bucket.invocation_logs]
}

run "budget_and_token_alarms_exist" {
  command = apply

  assert {
    condition     = aws_budgets_budget.bedrock.limit_amount == "200" && one([for n in aws_budgets_budget.bedrock.notification : n if n.notification_type == "ACTUAL"]).subscriber_email_addresses == toset(["platform@example.com"])
    error_message = "budget with default amount and notification"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.input_tokens) == 2 && aws_cloudwatch_metric_alarm.input_tokens["eu.vendor.model-v1:0"].dimensions["ModelId"] == "eu.vendor.model-v1:0" && aws_cloudwatch_metric_alarm.input_tokens["eu.vendor.model-v1:0"].metric_name == "InputTokenCount"
    error_message = "one InputTokenCount alarm per model id"
  }
}

run "budget_needs_a_recipient" {
  command = plan

  variables {
    budget_subscriber_emails = []
  }

  expect_failures = [var.budget_subscriber_emails]
}

run "admin_role_assumes_only_the_environment_read_roles" {
  command = plan

  variables {
    environment_role_arns = ["arn:aws:iam::111111111111:role/pay-dev-admin-agent", "arn:aws:iam::444444444444:role/pay-prod-admin-agent"]
  }

  assert {
    condition     = anytrue([for s in jsondecode(aws_iam_role_policy.admin[0].policy).Statement : s.Sid == "AssumeEnvironmentReadRoles" && toset(s.Resource) == toset(var.environment_role_arns) && s.Action == ["sts:AssumeRole"]])
    error_message = "sts:AssumeRole only on the environment read roles"
  }
}

run "admin_role_assume_target_must_be_an_admin_agent_role" {
  command = plan

  variables {
    environment_role_arns = ["arn:aws:iam::444444444444:role/OrganizationAccountAccessRole"]
  }

  expect_failures = [var.environment_role_arns]
}
