mock_provider "aws" {
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::333333333333:role/pay-stage-euc1-fis-experiment"
    }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:eu-central-1:333333333333:log-group:/fis/pay-stage-euc1"
    }
  }
  mock_resource "aws_ssm_document" {
    defaults = {
      arn = "arn:aws:ssm:eu-central-1:333333333333:document/pay-stage-chaos-memorydb-failover-shard"
    }
  }
}

variables {
  name_prefix              = "pay"
  environment              = "stage"
  region                   = "eu-central-1"
  region_short             = "euc1"
  account_id               = "333333333333"
  stop_alarm_arns          = ["arn:aws:cloudwatch:eu-central-1:333333333333:alarm:pay-stage-euc1-chaos-stop"]
  target_cell              = "cell-1"
  target_az                = "eu-central-1a"
  memorydb_cluster_name    = "pay-stage-euc1-memorydb-cell-1"
  log_kms_key_arn          = "arn:aws:kms:eu-central-1:333333333333:key/mrk-logs"
  permissions_boundary_arn = "arn:aws:iam::333333333333:policy/fis-boundary"
  tags = {
    team          = "platform"
    owner         = "platform@example.com"
    "pci-scope"   = "connected"
    "data-class"  = "internal"
    "backup-tier" = "none"
  }
}

run "stage_templates_match_tests_chaos" {
  command = apply

  assert {
    condition     = toset(keys(aws_fis_experiment_template.this)) == toset(["az-loss", "node-loss", "workers-spot-interruption", "aurora-writer-failover", "memorydb-failover"])
    error_message = "the five base experiments exist; pod actions stay off without eks_pod_actions"
  }

  assert {
    condition     = aws_iam_role.fis.name == "pay-stage-euc1-fis-experiment" && aws_cloudwatch_log_group.fis.name == "/fis/pay-stage-euc1" && aws_ssm_document.memorydb_failover.name == "pay-stage-chaos-memorydb-failover-shard"
    error_message = "names follow tests/chaos/fis"
  }

  assert {
    condition = alltrue([for t in aws_fis_experiment_template.this : (
      startswith(t.description, "Hypothesis:") && strcontains(t.description, "Stop: pay-stage-euc1-chaos-stop alarm.")
      && length(t.stop_condition) == 1 && one(t.stop_condition).source == "aws:cloudwatch:alarm"
      && one(t.log_configuration).cloudwatch_logs_configuration[0].log_group_arn == "arn:aws:logs:eu-central-1:333333333333:log-group:/fis/pay-stage-euc1:*"
      && one(t.experiment_options).empty_target_resolution_mode == "fail"
    )])
    error_message = "every template has a hypothesis, the stop alarm, the log group and fails on empty targets"
  }

  assert {
    condition = alltrue(flatten([for t in aws_fis_experiment_template.this : [
      for tg in t.target : contains([for rt in tg.resource_tag : "${rt.key}=${rt.value}"], "environment=stage")
    ]]))
    error_message = "every target requires the environment tag"
  }

  assert {
    condition     = contains(flatten([for tg in aws_fis_experiment_template.this["node-loss"].target : [for f in tg.filter : f.values]]), "eu-central-1a")
    error_message = "node loss stays in one AZ"
  }

  assert {
    condition     = alltrue([for s in jsondecode(aws_iam_role_policy.fis.policy).Statement : s.Resource != "*" if contains(flatten([s.Action]), "ec2:TerminateInstances") || contains(flatten([s.Action]), "rds:FailoverDBCluster")])
    error_message = "destructive actions are scoped to resource ARNs"
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.fis.policy).Statement[0].Condition.StringEquals["aws:ResourceTag/environment"] == "stage"
    error_message = "node termination needs the environment tag"
  }
}

run "prod_without_guard_has_no_templates" {
  command = apply

  variables {
    environment = "prod"
  }

  assert {
    condition     = length(aws_fis_experiment_template.this) == 0
    error_message = "prod creates no experiment template unless allow_prod"
  }
}

run "prod_with_guard_has_templates" {
  command = apply

  variables {
    environment = "prod"
    allow_prod  = true
  }

  assert {
    condition     = length(aws_fis_experiment_template.this) == 5
    error_message = "allow_prod enables the prod templates"
  }
}

run "pod_actions_and_psp_latency" {
  command = apply

  variables {
    eks_pod_actions = { cluster_name = "pay-stage-euc1-cell-1", service_account = "fis-experiment", namespace = "router", selector = "app.kubernetes.io/name=router" }
    psp_latency     = { namespace = "istio-egress", selector = "istio=egressgateway", destinations = ["psp-sandbox.example.com"] }
  }

  assert {
    condition     = contains(keys(aws_fis_experiment_template.this), "pod-loss") && contains(keys(aws_fis_experiment_template.this), "psp-egress-latency")
    error_message = "pod loss and PSP latency exist when pod actions are configured"
  }

  assert {
    condition     = one(aws_fis_experiment_template.this["psp-egress-latency"].target).parameters.availabilityZoneIdentifier == "eu-central-1a" && one(aws_fis_experiment_template.this["psp-egress-latency"].target).parameters.namespace == "istio-egress"
    error_message = "latency hits the egress pods of one AZ"
  }
}

run "latency_without_pod_actions_is_rejected" {
  command = plan

  variables {
    psp_latency = { namespace = "istio-egress", selector = "istio=egressgateway", destinations = ["psp-sandbox.example.com"] }
  }

  expect_failures = [var.psp_latency]
}

run "empty_stop_alarms_are_rejected" {
  command = plan

  variables {
    stop_alarm_arns = []
  }

  expect_failures = [var.stop_alarm_arns]
}

run "dev_is_rejected" {
  command = plan

  variables {
    environment = "dev"
  }

  expect_failures = [var.environment]
}
