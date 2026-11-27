mock_provider "aws" {
  mock_resource "aws_lb" {
    defaults = { arn = "arn:aws:elasticloadbalancing:eu-central-1:111111111111:loadbalancer/net/pay-dev-euc1-locker-endpoint/abc" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::111111111111:role/pay-dev-euc1-locker-endpoint-controller" }
  }
  mock_resource "aws_lb_target_group" {
    defaults = { arn = "arn:aws:elasticloadbalancing:eu-central-1:111111111111:targetgroup/pay-dev-euc1-locker/abc" }
  }
}

variables {
  name_prefix                  = "pay"
  environment                  = "dev"
  region                       = "eu-central-1"
  region_short                 = "euc1"
  account_id                   = "111111111111"
  vpc_id                       = "vpc-0abc"
  subnet_ids                   = ["subnet-a", "subnet-b", "subnet-c"]
  cluster_domain               = "dev.example.internal"
  client_security_group_ids    = ["sg-cell0", "sg-cell1"]
  locker_cluster_name          = "pay-dev-euc1-eks-locker"
  locker_cluster_arn           = "arn:aws:eks:eu-central-1:111111111111:cluster/pay-dev-euc1-eks-locker"
  locker_pod_security_group_id = "sg-lockerpod"
  permissions_boundary_arn     = "arn:aws:iam::111111111111:policy/workload-boundary"
  tags = {
    team = "payments-core", owner = "payments@example.com", pci-scope = "cde", data-class = "card-data", backup-tier = "none"
  }
}

run "host_matches_the_router_contract" {
  command = plan

  assert {
    condition     = output.host == "locker.payments.svc.locker.dev.example.internal" && output.url == "http://locker.payments.svc.locker.dev.example.internal:3001"
    error_message = "<service>.<namespace>.svc.locker.<cluster_domain>:3001"
  }
  assert {
    condition     = aws_lb.this.internal && aws_lb.this.load_balancer_type == "network"
    error_message = "internal NLB"
  }
}

run "only_cells_reach_the_locker" {
  command = plan

  assert {
    condition     = toset([for r in aws_vpc_security_group_ingress_rule.lb_from_cells : r.referenced_security_group_id]) == toset(var.client_security_group_ids)
    error_message = "the load balancer admits the cell node groups only"
  }
  assert {
    condition     = aws_vpc_security_group_egress_rule.lb_to_locker.referenced_security_group_id == "sg-lockerpod" && aws_vpc_security_group_ingress_rule.locker_from_lb.security_group_id == "sg-lockerpod"
    error_message = "the load balancer reaches the locker pods only"
  }
}

run "controller_only_registers_targets" {
  command = apply

  assert {
    condition = anytrue([for s in jsondecode(aws_iam_role_policy.controller.policy).Statement :
    s.Resource == ["arn:aws:elasticloadbalancing:eu-central-1:111111111111:targetgroup/pay-dev-euc1-locker/abc"] && contains(s.Action, "elasticloadbalancing:RegisterTargets")])
    error_message = "registration is limited to the locker target group"
  }
  assert {
    condition     = !strcontains(aws_iam_role_policy.controller.policy, "Authorize") && !strcontains(aws_iam_role_policy.controller.policy, "Create")
    error_message = "the controller cannot change security groups or create load balancers"
  }
}

run "locker_gateway_reaches_the_locker_on_its_port" {
  command = plan

  assert {
    condition     = aws_vpc_security_group_ingress_rule.locker_from_gateway.from_port == var.port && aws_vpc_security_group_ingress_rule.locker_from_gateway.referenced_security_group_id == var.locker_pod_security_group_id
    error_message = "the locker pod security group admits itself on the locker port only"
  }
}
