mock_provider "aws" {
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::222222222222:role/mock" }
  }
}

variables {
  name_prefix                = "pay"
  shared_services_account_id = "222222222222"
  permissions_boundary_arn   = "arn:aws:iam::222222222222:policy/workload-boundary"
  tags = {
    team = "platform", owner = "platform@example.com", pci-scope = "connected", data-class = "internal", backup-tier = "none"
  }
}

run "spoke_trusts_only_the_hub_controller" {
  command = plan

  variables {
    mode        = "spoke"
    environment = "dev"
    account_id  = "111111111111"
  }

  assert {
    condition     = aws_iam_role.spoke[0].name == "pay-dev-argocd-controller"
    error_message = "env.hcl access entries name pay-<env>-argocd-controller"
  }
  assert {
    condition     = jsondecode(aws_iam_role.spoke[0].assume_role_policy).Statement[0].Principal.AWS == "arn:aws:iam::222222222222:role/pay-shared-services-argocd-controller"
    error_message = "only the hub controller role may assume the spoke"
  }
  assert {
    condition     = length(aws_iam_role.controller) == 0 && length(aws_iam_role.writer) == 0
    error_message = "a spoke creates no hub roles"
  }
}

run "hub_assumes_spokes_and_binds_argocd_pods" {
  command = plan

  variables {
    mode              = "hub"
    environment       = "shared-services"
    account_id        = "222222222222"
    cluster_name      = "pay-shared-services-euc1-central"
    cluster_arn       = "arn:aws:eks:eu-central-1:222222222222:cluster/pay-shared-services-euc1-central"
    spoke_account_ids = { dev = "111111111111", stage = "333333333333", prod = "444444444444" }
  }

  assert {
    condition     = aws_iam_role.controller[0].name == "pay-shared-services-argocd-controller" && aws_iam_role.writer[0].name == "pay-shared-services-argocd-registration"
    error_message = "hub role names"
  }
  assert {
    condition     = toset(jsondecode(aws_iam_role_policy.controller[0].policy).Statement[0].Resource) == toset(["arn:aws:iam::111111111111:role/pay-dev-argocd-controller", "arn:aws:iam::333333333333:role/pay-stage-argocd-controller", "arn:aws:iam::444444444444:role/pay-prod-argocd-controller"])
    error_message = "the controller assumes exactly the spoke roles"
  }
  assert {
    condition     = toset(keys(aws_eks_pod_identity_association.controller)) == toset(["argocd-application-controller", "argocd-server"])
    error_message = "controller and server get the role"
  }
}

run "hub_needs_the_cluster" {
  command = plan

  variables {
    mode              = "hub"
    environment       = "shared-services"
    account_id        = "222222222222"
    spoke_account_ids = { dev = "111111111111" }
  }

  expect_failures = [aws_iam_role.controller]
}
