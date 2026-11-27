mock_provider "aws" {}

variables {
  name_prefix              = "pay"
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
    condition     = jsondecode(aws_iam_role.plan.assume_role_policy).Statement[0].Condition.StringLike["token.actions.githubusercontent.com:sub"] == ["repo:example-org/payments-platform:ref:refs/heads/main"]
    error_message = "plan only from main of this repository"
  }
  assert {
    condition     = jsondecode(aws_iam_role.apply["network"].assume_role_policy).Statement[0].Condition.StringLike["token.actions.githubusercontent.com:sub"] == ["repo:example-org/payments-platform:ref:refs/heads/main", "repo:example-org/payments-platform:ref:refs/heads/release/*"]
    error_message = "apply only from main and release branches of this repository"
  }
  assert {
    condition     = jsondecode(aws_iam_role.apply["network"].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:aud"] == "sts.amazonaws.com"
    error_message = "the audience is STS"
  }
}

run "no_wildcard_subject_except_the_release_suffix" {
  command = plan

  assert {
    condition = alltrue(flatten([
      for r in values(aws_iam_role.apply) : [
        for s in jsondecode(r.assume_role_policy).Statement[0].Condition.StringLike["token.actions.githubusercontent.com:sub"] :
        !strcontains(s, "*") || endswith(s, ":ref:refs/heads/release/*")
      ]
    ])) && !strcontains(jsondecode(aws_iam_role.plan.assume_role_policy).Statement[0].Condition.StringLike["token.actions.githubusercontent.com:sub"][0], "*")
    error_message = "a subject may contain * only as the release/* suffix of an apply role"
  }
}

run "other_branches_and_wildcards_are_rejected" {
  command = plan

  variables {
    apply_refs = ["refs/heads/*"]
  }

  expect_failures = [var.apply_refs]
}

run "feature_branch_is_rejected" {
  command = plan

  variables {
    apply_refs = ["refs/heads/main", "refs/heads/feat/x"]
  }

  expect_failures = [var.apply_refs]
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
    condition     = length([for s in jsondecode(aws_iam_role_policy.apply["network"].policy).Statement : s if s.Sid == "StateOfThisComponent" && contains(s.Resource, "arn:aws:s3:::pay-prod-euc1-tf-state-444444444444/prod/*/network/terraform.tfstate")]) == 1
    error_message = "state access limited to the keys of its component"
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

run "no_role_trusts_pull_requests" {
  command = plan

  variables {
    ecr_read_repository_arns = ["arn:aws:ecr:eu-central-1:444444444444:repository/payments/*"]
  }

  assert {
    condition = alltrue(flatten([
      for r in concat([aws_iam_role.plan], values(aws_iam_role.apply), aws_iam_role.ecr_read) : [
        for s in jsondecode(r.assume_role_policy).Statement[0].Condition.StringLike["token.actions.githubusercontent.com:sub"] : !strcontains(s, "pull_request")
      ]
    ]))
    error_message = "a pull request may not read state or assume any role"
  }
}

run "plan_without_refs_is_rejected" {
  command = plan

  variables {
    plan_refs = []
  }

  expect_failures = [var.plan_refs]
}

run "plan_from_a_pull_request_subject_is_rejected" {
  command = plan

  variables {
    plan_refs = ["pull_request"]
  }

  expect_failures = [var.plan_refs]
}

run "plan_from_other_branches_is_rejected" {
  command = plan

  variables {
    plan_refs = ["refs/heads/release/*"]
  }

  expect_failures = [var.plan_refs]
}

run "ecr_read_role_reads_named_repositories_from_main" {
  command = plan

  variables {
    environment              = "shared-services"
    ecr_read_repository_arns = ["arn:aws:ecr:eu-central-1:444444444444:repository/payments/*"]
  }

  assert {
    condition     = aws_iam_role.ecr_read[0].name == "pay-shared-services-glob-ecr-read" && aws_iam_role.plan.name == "pay-shared-services-glob-tf-plan"
    error_message = "shared-services role names"
  }
  assert {
    condition     = jsondecode(aws_iam_role.ecr_read[0].assume_role_policy).Statement[0].Condition.StringLike["token.actions.githubusercontent.com:sub"] == ["repo:example-org/payments-platform:ref:refs/heads/main"]
    error_message = "ecr-read only from main"
  }
  assert {
    condition = alltrue([
      for s in jsondecode(aws_iam_role_policy.ecr_read[0].policy).Statement :
      alltrue([for a in s.Action : !contains(["ecr:PutImage", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload", "ecr:BatchDeleteImage"], a)])
    ]) && length([for s in jsondecode(aws_iam_role_policy.ecr_read[0].policy).Statement : s if s.Resource == "*" && s.Action != ["ecr:GetAuthorizationToken"]]) == 0
    error_message = "read only; only the token call is unscoped"
  }
}

run "no_ecr_read_role_without_repositories" {
  command = plan

  assert {
    condition     = length(aws_iam_role.ecr_read) == 0 && output.ecr_read_role_arn == null
    error_message = "no repositories, no role"
  }
}

run "dr_apply_role_trusts_its_environment_and_reaches_both_state_buckets" {
  command = plan

  variables {
    dr_apply = {
      github_environment        = "dr-compute-prod"
      state_replica_bucket_arn  = "arn:aws:s3:::pay-prod-use1-tf-state-222222222222"
      state_replica_kms_key_arn = "arn:aws:kms:us-east-1:222222222222:key/mrk-0123456789abcdef0123456789abcdef"
      actions                   = ["eks:CreateCluster"]
      resource_arns             = ["arn:aws:eks:us-east-1:444444444444:cluster/pay-prod-use1-*"]
    }
  }

  assert {
    condition     = aws_iam_role.dr_apply[0].name == "pay-prod-glob-dr-apply" && aws_iam_role.dr_apply[0].permissions_boundary == var.permissions_boundary_arn
    error_message = "named pay-<env>-glob-dr-apply with the boundary"
  }
  assert {
    condition     = jsondecode(aws_iam_role.dr_apply[0].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:example-org/payments-platform:environment:dr-compute-prod"
    error_message = "only jobs of the dr-compute-prod environment"
  }
  assert {
    condition = one([for s in jsondecode(aws_iam_role_policy.dr_apply[0].policy).Statement : s.Resource if s.Sid == "EnvironmentState"]) == [
      "arn:aws:s3:::pay-prod-euc1-tf-state-444444444444/prod/*", "arn:aws:s3:::pay-prod-use1-tf-state-222222222222/prod/*",
    ]
    error_message = "read and write prod/ in the working bucket and the replica"
  }
  assert {
    condition     = length(one([for s in jsondecode(aws_iam_role_policy.dr_apply[0].policy).Statement : s.Resource if s.Sid == "StateKeys"])) == 2
    error_message = "both state keys"
  }
}

run "no_dr_apply_role_by_default" {
  command = plan

  assert {
    condition     = length(aws_iam_role.dr_apply) == 0
    error_message = "no DR role without dr_apply"
  }
}

run "dr_apply_from_another_environment_rejected" {
  command = plan

  variables {
    dr_apply = {
      github_environment        = "prod"
      state_replica_bucket_arn  = "arn:aws:s3:::pay-prod-use1-tf-state-222222222222"
      state_replica_kms_key_arn = "arn:aws:kms:us-east-1:222222222222:key/mrk-0123456789abcdef0123456789abcdef"
      actions                   = ["iam:*"]
      resource_arns             = ["*"]
    }
  }

  expect_failures = [var.dr_apply]
}

run "component_roles_follow_the_live_tree_and_the_real_state_keys" {
  command = plan

  variables {
    apply_components = ["eks", "vpc"]
    exec_account_ids = ["444444444444"]
  }

  assert {
    condition     = aws_iam_role.component_apply["eks"].name == "pay-prod-glob-tf-apply-eks"
    error_message = "role name pay-<env>-glob-tf-apply-<component>"
  }
  assert {
    condition = anytrue([for s in jsondecode(aws_iam_role_policy.component_apply["eks"].policy).Statement : s.Sid == "StateOfThisComponent" &&
    contains(s.Resource, "arn:aws:s3:::pay-prod-euc1-tf-state-444444444444/prod/*/eks/terraform.tfstate")])
    error_message = "state of <env>/<region>/[<cell>/]<component>/terraform.tfstate"
  }
  assert {
    condition     = jsondecode(aws_iam_role.component_apply["eks"].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:example-org/payments-platform:environment:prod"
    error_message = "subject environment:<env>"
  }
  assert {
    condition     = anytrue([for s in jsondecode(aws_iam_role_policy.component_apply["eks"].policy).Statement : s.Sid == "AssumeExecRole" && s.Resource == ["arn:aws:iam::444444444444:role/pay-prod-tf-exec"]])
    error_message = "the apply role reaches the account through pay-<env>-tf-exec"
  }
}

run "plan_reaches_the_account_through_the_exec_role" {
  command = plan

  variables {
    exec_account_ids = ["444444444444"]
  }

  assert {
    condition     = anytrue([for s in jsondecode(aws_iam_role_policy.plan.policy).Statement : s.Sid == "AssumeExecRole"])
    error_message = "plan assumes the exec role"
  }
}
