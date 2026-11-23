mock_provider "aws" {}

variables {
  name_prefix              = "acme"
  account_id               = "123456789012"
  region                   = "eu-central-1"
  permissions_boundary_arn = "arn:aws:iam::123456789012:policy/boundary"
  vpc_id                   = "vpc-00000001"
  subnet_ids               = ["subnet-a", "subnet-b", "subnet-c"]
  untrusted_subnet_ids     = ["subnet-x", "subnet-y"]
  ebs_kms_key_arn          = "arn:aws:kms:eu-central-1:123456789012:key/mrk-ebs"
  runner_version           = "2.329.0"
  runner_sha256            = "abababababababababababababababababababababababababababababababab"
  github_oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
  github_repository        = "acme/platform"
  ecr_repository_arns      = ["arn:aws:ecr:eu-central-1:123456789012:repository/payments/*"]
  plan_role_arns           = ["arn:aws:iam::333333333333:role/acme-stage-tf-plan"]
  tags                     = { team = "platform" }
  pools = {
    ci-build = { instance_types = ["c7gd.4xlarge", "c6gd.4xlarge"], min_size = 0, warm_size = 1, max_size = 8, root_volume_gb = 30, on_demand_base = 0, target_cpu = 50, labels = ["build"], cache_write = true, ecr_pull = true, assume_plan = false, untrusted = false }
    ci-test  = { instance_types = ["m7g.2xlarge"], min_size = 0, warm_size = 1, max_size = 16, root_volume_gb = 40, on_demand_base = 0, target_cpu = 50, labels = [], cache_write = false, ecr_pull = true, assume_plan = false, untrusted = false }
    ci-light = { instance_types = ["m7g.large"], min_size = 0, warm_size = 1, max_size = 20, root_volume_gb = 30, on_demand_base = 0, target_cpu = 50, labels = [], cache_write = false, ecr_pull = false, assume_plan = true, untrusted = false }
    ci-pr    = { instance_types = ["c7g.2xlarge", "m7g.2xlarge"], min_size = 0, warm_size = 1, max_size = 20, root_volume_gb = 40, on_demand_base = 0, target_cpu = 50, labels = [], cache_write = false, ecr_pull = false, assume_plan = false, untrusted = true }
  }
}

run "one_group_secret_role_and_profile_per_pool" {
  command = plan

  assert {
    condition     = length(aws_autoscaling_group.pool) == 4 && length(aws_secretsmanager_secret.github_app) == 4 && length(aws_iam_role.runner) == 4 && length(aws_iam_instance_profile.runner) == 4
    error_message = "each pool needs its own group, secret, role and instance profile"
  }
  assert {
    condition     = aws_secretsmanager_secret.github_app["ci-pr"].name == "acme/ci/github-app/ci-pr" && aws_autoscaling_group.pool["ci-build"].name == "acme-ci-ci-build"
    error_message = "names follow the prefix and the pool"
  }
}

run "pools_run_on_spot_with_alternative_instance_types" {
  command = plan

  assert {
    condition     = alltrue([for g in aws_autoscaling_group.pool : g.mixed_instances_policy[0].instances_distribution[0].on_demand_percentage_above_base_capacity == 0 && g.mixed_instances_policy[0].instances_distribution[0].spot_allocation_strategy == "price-capacity-optimized"])
    error_message = "everything above the On-Demand base is Spot"
  }
  assert {
    condition     = length(aws_autoscaling_group.pool["ci-build"].mixed_instances_policy[0].launch_template[0].override) == 2 && aws_autoscaling_group.pool["ci-build"].capacity_rebalance
    error_message = "several instance types and capacity rebalancing keep a pool alive when one type has no Spot capacity"
  }
  assert {
    condition     = alltrue([for g in aws_autoscaling_group.pool : length(g.instance_refresh) == 1])
    error_message = "a new launch template replaces the instances in turn"
  }
}

run "launch_template_hardens_the_instance" {
  command = plan

  assert {
    condition     = alltrue([for t in aws_launch_template.pool : t.metadata_options[0].http_tokens == "required" && t.metadata_options[0].http_put_response_hop_limit == 1])
    error_message = "IMDSv2 only and one hop, so containers cannot reach the role credentials"
  }
  assert {
    condition     = alltrue([for t in aws_launch_template.pool : t.block_device_mappings[0].ebs[0].encrypted == "true" && t.network_interfaces[0].associate_public_ip_address == "false"])
    error_message = "encrypted volumes and no public address"
  }
  assert {
    condition     = alltrue([for s in aws_security_group.pool : length(s.egress) == 1 && one(s.egress).from_port == 443])
    error_message = "outbound HTTPS only"
  }
}

run "untrusted_pool_blocks_metadata_and_uses_own_subnets" {
  command = plan

  assert {
    condition     = can(regex("iptables -I OUTPUT", base64decode(aws_launch_template.pool["ci-pr"].user_data))) && !can(regex("iptables -I OUTPUT", base64decode(aws_launch_template.pool["ci-build"].user_data)))
    error_message = "only the untrusted pool blocks the runner user from the instance metadata"
  }
  assert {
    condition     = aws_autoscaling_group.pool["ci-pr"].vpc_zone_identifier == toset(["subnet-x", "subnet-y"]) && aws_autoscaling_group.pool["ci-test"].vpc_zone_identifier == toset(["subnet-a", "subnet-b", "subnet-c"])
    error_message = "the untrusted pool has subnets of its own"
  }
}

run "runner_installs_pinned_and_registers_with_labels" {
  command = plan

  assert {
    condition     = can(regex("actions-runner-linux-arm64-2.329.0.tar.gz", base64decode(aws_launch_template.pool["ci-test"].user_data))) && can(regex("sha256sum -c", base64decode(aws_launch_template.pool["ci-test"].user_data)))
    error_message = "the runner archive is pinned and verified"
  }
  assert {
    condition     = can(regex("self-hosted,linux,arm64,ci-build,build", base64decode(aws_launch_template.pool["ci-build"].user_data)))
    error_message = "labels are self-hosted, linux, arm64, the pool name and the extra labels"
  }
}

run "warm_instances_only_in_working_hours" {
  command = plan

  assert {
    condition     = length(aws_autoscaling_schedule.work_start) == 4 && aws_autoscaling_schedule.work_start["ci-build"].min_size == 1 && aws_autoscaling_schedule.work_end["ci-build"].min_size == 0
    error_message = "each pool rises to warm_size in the morning and returns to min_size in the evening"
  }
  assert {
    condition     = alltrue([for p in aws_autoscaling_policy.cpu : p.policy_type == "TargetTrackingScaling" && p.target_tracking_configuration[0].predefined_metric_specification[0].predefined_metric_type == "ASGAverageCPUUtilization"])
    error_message = "capacity follows the average CPU"
  }
}

run "roles_decide_what_a_pool_may_do" {
  command = apply

  assert {
    condition     = can(regex("s3:PutObject", aws_iam_role_policy.runner["ci-build"].policy)) && !can(regex("s3:PutObject", aws_iam_role_policy.runner["ci-test"].policy))
    error_message = "only the build pool writes the cache"
  }
  assert {
    condition     = can(regex("tf-plan", aws_iam_role_policy.runner["ci-light"].policy)) && !can(regex("tf-plan", aws_iam_role_policy.runner["ci-build"].policy))
    error_message = "only the plan-role pool may reach the plan roles"
  }
  assert {
    condition     = can(regex("\"Effect\":\"Deny\"", aws_iam_role_policy.runner["ci-pr"].policy)) && !can(regex("ecr:BatchGetImage", aws_iam_role_policy.runner["ci-pr"].policy))
    error_message = "the untrusted pool is denied roles and the registry"
  }
  assert {
    condition     = can(regex("ec2.amazonaws.com", aws_iam_role.runner["ci-pr"].assume_role_policy))
    error_message = "instances assume the role through the EC2 service"
  }
}

run "cache_bucket_is_private_encrypted_and_expiring" {
  command = plan

  assert {
    condition     = aws_s3_bucket.cache.bucket == "acme-ci-cache-123456789012" && aws_s3_bucket_public_access_block.cache.block_public_acls && aws_s3_bucket_public_access_block.cache.restrict_public_buckets
    error_message = "the cache bucket is private"
  }
  assert {
    condition     = one(aws_s3_bucket_lifecycle_configuration.cache.rule).expiration[0].days == 14
    error_message = "cache objects expire after 14 days by default"
  }
}

run "push_role_trusts_only_main_and_release_refs" {
  command = plan

  assert {
    condition     = can(regex("repo:acme/platform:ref:refs/heads/main", aws_iam_role.github_push.assume_role_policy)) && can(regex("refs/heads/release/\\*", aws_iam_role.github_push.assume_role_policy))
    error_message = "the push role is limited to main and release/* of the repository"
  }
}

run "untrusted_pool_may_not_hold_rights" {
  command = plan

  variables {
    pools = {
      ci-pr = { instance_types = ["c7g.2xlarge"], min_size = 0, warm_size = 0, max_size = 4, root_volume_gb = 40, on_demand_base = 0, target_cpu = 50, labels = [], cache_write = true, ecr_pull = false, assume_plan = false, untrusted = true }
    }
  }

  expect_failures = [var.pools]
}

run "pool_sizes_are_ordered" {
  command = plan

  variables {
    pools = {
      ci-test = { instance_types = ["m7g.2xlarge"], min_size = 3, warm_size = 1, max_size = 4, root_volume_gb = 40, on_demand_base = 0, target_cpu = 50, labels = [], cache_write = false, ecr_pull = true, assume_plan = false, untrusted = false }
    }
  }

  expect_failures = [var.pools]
}

run "bad_account_id_is_rejected" {
  command = plan

  variables {
    account_id = "123"
  }

  expect_failures = [var.account_id]
}

run "placeholder_checksum_is_rejected" {
  command = plan

  variables {
    runner_sha256 = "0000000000000000000000000000000000000000000000000000000000000000"
  }

  expect_failures = [var.runner_sha256]
}
