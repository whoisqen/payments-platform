mock_provider "aws" {
  mock_data "aws_lb" {
    defaults = {
      dns_name = "internal-gw-123.elb.eu-central-1.amazonaws.com"
      zone_id  = "Z3F0SRJ5LGBH90"
    }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::222222222222:role/mock" }
  }
  mock_resource "aws_acmpca_certificate_authority" {
    defaults = { arn = "arn:aws:acm-pca:eu-central-1:222222222222:certificate-authority/mock" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "222222222222" }
  }
}

variables {
  name_prefix              = "pay"
  zone_name                = "admin.example.test"
  vpc_ids                  = ["vpc-0aaa", "vpc-0bbb"]
  cluster_name             = "pay-shared-services-euc1-central"
  permissions_boundary_arn = "arn:aws:iam::222222222222:policy/boundary"
  ca_organization          = "Example"
  tags = {
    team          = "platform"
    owner         = "platform@example.com"
    "pci-scope"   = "out-of-scope"
    "data-class"  = "internal"
    "backup-tier" = "none"
  }
}

run "first_step_has_zone_ca_and_roles_but_no_record" {
  command = apply

  assert {
    condition     = aws_route53_zone.admin.name == "admin.example.test" && length(aws_route53_zone.admin.vpc) == 1 && length(aws_route53_zone_association.extra) == 1
    error_message = "private zone attached to both VPCs, the second through an association"
  }

  assert {
    condition     = length(aws_route53_record.wildcard) == 0 && length(data.aws_lb.gateway) == 0
    error_message = "no NLB lookup and no record while nlb_lookup_enabled is false"
  }

  assert {
    condition     = aws_acmpca_certificate_authority.root.type == "ROOT" && !aws_acmpca_certificate_authority.root.revocation_configuration[0].crl_configuration[0].enabled
    error_message = "root CA without revocation"
  }

  assert {
    condition     = length(aws_iam_role.this) == 2 && alltrue([for r in values(aws_iam_role.this) : r.permissions_boundary == var.permissions_boundary_arn])
    error_message = "two roles with the boundary"
  }

  assert {
    condition     = aws_eks_pod_identity_association.this["privateca-issuer"].service_account == "aws-privateca-issuer" && aws_eks_pod_identity_association.this["load-balancer-controller"].namespace == "kube-system"
    error_message = "associations use the default service accounts"
  }

  assert {
    condition     = output.wildcard_fqdn == "*.admin.example.test" && !output.wildcard_record_created
    error_message = "wildcard name is known before the record exists"
  }
}

run "second_step_adds_the_wildcard_alias" {
  command = apply

  variables {
    nlb_lookup_enabled = true
    nlb_stack_tag      = "istio-system/admin-gateway"
  }

  assert {
    condition     = aws_route53_record.wildcard[0].name == "*.admin.example.test" && aws_route53_record.wildcard[0].type == "A"
    error_message = "wildcard A alias in the zone"
  }

  assert {
    condition     = output.wildcard_record_created
    error_message = "output reports the record"
  }
}

run "lookup_without_a_stack_tag_is_refused" {
  command = plan

  variables {
    nlb_lookup_enabled = true
  }

  expect_failures = [data.aws_lb.gateway]
}

run "issuer_policy_is_limited_to_the_one_ca" {
  command = apply

  assert {
    condition     = length(jsondecode(aws_iam_role_policy.privateca_issuer.policy).Statement) == 1 && length(jsondecode(aws_iam_role_policy.privateca_issuer.policy).Statement[0].Action) == 3
    error_message = "three actions in one statement"
  }
}

run "tags_are_required" {
  command = plan

  variables {
    tags = { team = "platform" }
  }

  expect_failures = [var.tags]
}

run "zone_must_have_a_vpc" {
  command = plan

  variables {
    vpc_ids = []
  }

  expect_failures = [var.vpc_ids]
}

run "spoke_vpcs_are_authorized_and_nlbs_admit_only_the_listed_ports" {
  command = plan

  variables {
    spoke_vpcs = {
      dev-euc1  = { vpc_id = "vpc-0dev", region = "eu-central-1" }
      prod-use1 = { vpc_id = "vpc-0use1", region = "us-east-1" }
    }
    nlb_security_group = {
      vpc_id      = "vpc-0aaa"
      spoke_cidrs = ["10.120.0.0/16", "10.151.0.0/16"]
      local_cidrs = ["10.140.0.0/16"]
    }
  }

  assert {
    condition     = length(aws_route53_vpc_association_authorization.spoke) == 2 && aws_route53_vpc_association_authorization.spoke["prod-use1"].vpc_region == "us-east-1"
    error_message = "each environment VPC is authorized in its own region"
  }
  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.nlb) == 7 && alltrue([for r in values(aws_vpc_security_group_ingress_rule.nlb) : contains([443, 4317, 8443], r.from_port) && r.from_port == r.to_port])
    error_message = "two environments on three ports plus the local VPC on 443, nothing else"
  }
  assert {
    condition     = alltrue([for r in values(aws_vpc_security_group_ingress_rule.nlb) : r.cidr_ipv4 != "10.140.0.0/16" || r.from_port == 443])
    error_message = "the local VPC reaches only the gateway listener"
  }
}

run "nlb_ports_are_limited" {
  command = plan

  variables {
    nlb_security_group = {
      vpc_id      = "vpc-0aaa"
      spoke_cidrs = ["10.120.0.0/16"]
      spoke_ports = [22]
      local_cidrs = ["10.140.0.0/16"]
    }
  }

  expect_failures = [var.nlb_security_group]
}

run "ingest_records_point_to_their_own_nlb" {
  command = plan

  variables {
    nlb_lookup_enabled = true
    nlb_stack_tag      = "istio-ingress-admin/admin"
    ingest_records = {
      "metrics-ingest" = "istio-ingress-admin/ingest"
      "logs-ingest"    = "monitoring/logs"
    }
  }

  assert {
    condition     = aws_route53_record.ingest["metrics-ingest"].name == "metrics-ingest.admin.example.test" && length(data.aws_lb.ingest) == 2
    error_message = "every ingest host needs its record and one NLB lookup per distinct stack"
  }
}
