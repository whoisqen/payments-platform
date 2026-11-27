mock_provider "aws" {}

variables {
  name_prefix = "pay"
  environment = "prod"
  endpoint_groups = {
    "eu-central-1" = {
      active        = true
      endpoint_arns = ["arn:aws:elasticloadbalancing:eu-central-1:111111111111:loadbalancer/net/pay-prod-euc1-ingress/0123456789abcdef"]
    }
    "us-east-1" = {
      active        = false
      endpoint_arns = ["arn:aws:elasticloadbalancing:us-east-1:111111111111:loadbalancer/net/pay-prod-use1-ingress/0123456789abcdef"]
    }
  }
  tags = {
    environment = "prod", team = "platform", owner = "platform@example.com", cost-center = "cc-100", cell = "shared"
    component   = "edge", pci-scope = "connected", data-class = "internal", backup-tier = "none", managed-by = "terraform", repo = "infra/modules/global-accelerator"
  }
}

run "listener_and_groups" {
  command = plan

  assert {
    condition     = aws_globalaccelerator_accelerator.this.name == "pay-prod-glob-edge" && aws_globalaccelerator_listener.this.protocol == "TCP"
    error_message = "accelerator name and TCP listener"
  }
  assert {
    condition     = length(aws_globalaccelerator_endpoint_group.this) == 2
    error_message = "one group per region"
  }
}

run "recovery_groups_have_weight_zero" {
  command = plan

  assert {
    condition     = alltrue([for e in aws_globalaccelerator_endpoint_group.this["us-east-1"].endpoint_configuration : e.weight == 0]) && aws_globalaccelerator_endpoint_group.this["us-east-1"].traffic_dial_percentage == 0
    error_message = "recovery groups take no traffic"
  }
  assert {
    condition     = aws_globalaccelerator_endpoint_group.this["eu-central-1"].traffic_dial_percentage == 100 && alltrue([for e in aws_globalaccelerator_endpoint_group.this["eu-central-1"].endpoint_configuration : e.weight == 128])
    error_message = "the writing region takes all traffic"
  }
}

run "two_active_groups_rejected" {
  command = plan

  variables {
    endpoint_groups = {
      "eu-central-1" = { active = true }
      "us-east-1"    = { active = true }
    }
  }

  expect_failures = [var.endpoint_groups]
}

run "edge_load_balancers_are_found_by_tag" {
  command = plan

  override_data {
    target = data.aws_lbs.edge["eu-central-1"]
    values = { arns = ["arn:aws:elasticloadbalancing:eu-central-1:111111111111:loadbalancer/net/k8s-edge/abc"] }
  }

  variables {
    endpoint_groups = {
      "eu-central-1" = { active = true, endpoint_lb_tags = { "elbv2.k8s.aws/cluster" = "pay-prod-euc1-eks-edge", "pay.io/edge-entry" = "true" } }
      "us-east-1"    = { active = false }
    }
  }

  assert {
    condition     = [for e in aws_globalaccelerator_endpoint_group.this["eu-central-1"].endpoint_configuration : e.endpoint_id] == ["arn:aws:elasticloadbalancing:eu-central-1:111111111111:loadbalancer/net/k8s-edge/abc"]
    error_message = "the tagged edge load balancer is the endpoint"
  }
  assert {
    condition     = aws_globalaccelerator_endpoint_group.this["eu-central-1"].health_check_path == "/health/ready"
    error_message = "the accelerator checks the readiness path the router serves"
  }
}
