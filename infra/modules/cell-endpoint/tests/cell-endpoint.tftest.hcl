mock_provider "aws" {
  mock_resource "aws_lb" {
    defaults = { arn = "arn:aws:elasticloadbalancing:eu-central-1:111111111111:loadbalancer/net/pay-dev-euc1-cell-0-endpoint/abc" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::111111111111:role/pay-dev-euc1-cell-0-endpoint-controller" }
  }
  mock_resource "aws_lb_target_group" {
    defaults = { arn = "arn:aws:elasticloadbalancing:eu-central-1:111111111111:targetgroup/pay-dev-euc1-cell-0-rtr/abc" }
  }
}

variables {
  name_prefix               = "pay"
  environment               = "dev"
  region                    = "eu-central-1"
  region_short              = "euc1"
  account_id                = "111111111111"
  vpc_id                    = "vpc-0abc"
  subnet_ids                = ["subnet-a", "subnet-b", "subnet-c"]
  cluster_domain            = "dev.example.internal"
  cell                      = "cell-0"
  client_security_group_ids = ["sg-edge"]
  cell_cluster_name         = "pay-dev-euc1-eks-cell-0"
  cell_cluster_arn          = "arn:aws:eks:eu-central-1:111111111111:cluster/pay-dev-euc1-eks-cell-0"
  target_security_group_id  = "sg-cell0-nodes"
  permissions_boundary_arn  = "arn:aws:iam::111111111111:policy/workload-boundary"
  tags = {
    team = "payments-core", owner = "payments@example.com", pci-scope = "cde", data-class = "card-data", backup-tier = "none"
  }
}

run "host_matches_the_edge_contract" {
  command = plan

  assert {
    condition     = output.host == "router.payments.svc.cell-0.dev.example.internal" && aws_route53_zone.this.name == "cell-0.dev.example.internal"
    error_message = "router.payments.svc.<cell>.<cluster_domain> in its own private zone"
  }
  assert {
    condition     = aws_lb.this.internal && aws_lb.this.load_balancer_type == "network" && aws_lb_listener.this.port == 8443
    error_message = "an internal NLB on the gateway port"
  }
}

run "only_the_edge_reaches_the_gateway" {
  command = plan

  assert {
    condition     = keys(aws_vpc_security_group_ingress_rule.lb_from_edge) == ["sg-edge"] && aws_vpc_security_group_ingress_rule.gateway_from_lb.security_group_id == "sg-cell0-nodes"
    error_message = "edge nodes into the load balancer, the load balancer into the cell nodes on the gateway port"
  }
  assert {
    condition     = jsondecode(aws_iam_role.controller.assume_role_policy).Statement[0].Condition.ArnEquals["aws:SourceArn"] == var.cell_cluster_arn
    error_message = "the controller role trusts pods of the cell cluster only"
  }
}

run "rejects_an_unknown_cell" {
  command = plan

  variables {
    cell = "cell-9"
  }

  expect_failures = [var.cell]
}
