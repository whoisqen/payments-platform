mock_provider "aws" {}

variables {
  account_id               = "444444444444"
  environment              = "prod"
  github_repository        = "example-org/payments-platform"
  create_oidc_provider     = false
  permissions_boundary_arn = "arn:aws:iam::444444444444:policy/workload-boundary"
  state_bucket_arn         = "arn:aws:s3:::pay-prod-euc1-tf-state-444444444444"
  state_kms_key_arn        = "arn:aws:kms:eu-central-1:444444444444:key/mrk-0123456789abcdef0123456789abcdef"
  apply_roles = {
    network = {
      github_environment = "prod-network"
      actions            = ["ec2:ModifyVpcAttribute", "ec2:DeleteVpc"]
      resource_arns      = ["arn:aws:ec2:eu-central-1:444444444444:vpc/*"]
      unscoped_actions   = ["ec2:CreateVpc"]
    }
  }
  tags = {
    environment = "prod", team = "platform", owner = "platform@example.com", cost-center = "cc-100", cell = "shared"
    component   = "ci", pci-scope = "connected", data-class = "internal", backup-tier = "none", managed-by = "terraform", repo = "infra/modules/ci-oidc-roles"
  }
}

run "provider_and_role_names" {
  command = plan

  variables {
    create_oidc_provider = true
  }

  assert {
    condition     = aws_iam_openid_connect_provider.github[0].url == "https://token.actions.githubusercontent.com" && contains(aws_iam_openid_connect_provider.github[0].client_id_list, "sts.amazonaws.com")
    error_message = "GitHub OIDC provider with the STS audience"
  }
  assert {
    condition     = aws_iam_role.plan.name == "pay-prod-glob-tf-plan" && aws_iam_role.apply["network"].name == "pay-prod-glob-tf-apply-network"
    error_message = "role names follow pay-<env>-glob-..."
  }
  assert {
    condition     = aws_iam_role.plan.max_session_duration == 3600 && aws_iam_role.apply["network"].permissions_boundary == var.permissions_boundary_arn
    error_message = "1 hour sessions and the boundary"
  }
}

run "trust_is_pinned_to_repository_and_context" {
  command = plan

  assert {
    condition     = jsondecode(aws_iam_role.plan.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:example-org/payments-platform:pull_request"
    error_message = "plan only from pull requests of this repository"
  }
  assert {
    condition     = jsondecode(aws_iam_role.apply["network"].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:example-org/payments-platform:environment:prod-network"
    error_message = "apply only from its GitHub environment"
  }
}

run "plan_cannot_write_state_or_read_secrets" {
  command = plan

  assert {
    condition     = alltrue([for s in jsondecode(aws_iam_role_policy.plan.policy).Statement : endswith(s.Resource, ".tflock") if s.Sid == "StateLockOnly"])
    error_message = "plan writes only lock files"
  }
  assert {
    condition     = length([for s in jsondecode(aws_iam_role_policy.plan.policy).Statement : s if s.Sid == "NoSecretValues" && s.Effect == "Deny"]) == 1
    error_message = "secret reads are denied"
  }
}

run "apply_state_prefix_is_its_own" {
  command = plan

  assert {
    condition     = length([for s in jsondecode(aws_iam_role_policy.apply["network"].policy).Statement : s if s.Sid == "StateOfThisComponent" && endswith(s.Resource, "/prod/network/*")]) == 1
    error_message = "state access limited to <env>/<component>/"
  }
  assert {
    condition     = length([for s in jsondecode(aws_iam_role_policy.apply["network"].policy).Statement : s if s.Sid == "RolesNeedTheBoundary"]) == 1
    error_message = "boundary is enforced on created roles"
  }
}

run "existing_provider_is_reused" {
  command = plan

  assert {
    condition     = length(aws_iam_openid_connect_provider.github) == 0 && output.oidc_provider_arn == "arn:aws:iam::444444444444:oidc-provider/token.actions.githubusercontent.com"
    error_message = "reuse the account's provider"
  }
}

run "wildcard_action_rejected" {
  command = plan

  variables {
    apply_roles = {
      bad = { github_environment = "x", actions = ["iam:*"], resource_arns = ["arn:aws:s3:::b"] }
    }
  }

  expect_failures = [var.apply_roles]
}

run "wildcard_resource_rejected" {
  command = plan

  variables {
    apply_roles = {
      bad = { github_environment = "x", actions = ["s3:GetObject"], resource_arns = ["*"] }
    }
  }

  expect_failures = [var.apply_roles]
}
