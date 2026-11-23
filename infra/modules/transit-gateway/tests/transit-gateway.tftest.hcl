mock_provider "aws" {}

variables {
  name_prefix  = "pay"
  region       = "eu-central-1"
  environment  = "prod"
  route_tables = ["cde", "egress", "inspection"]
  attachments = {
    cde = {
      vpc_id       = "vpc-0000000000000cde0"
      subnet_ids   = ["subnet-a", "subnet-b", "subnet-c"]
      route_table  = "cde"
      propagate_to = ["egress"]
    }
    egress = {
      vpc_id         = "vpc-000000000000egre0"
      subnet_ids     = ["subnet-d", "subnet-e", "subnet-f"]
      route_table    = "egress"
      propagate_to   = ["cde"]
      appliance_mode = true
    }
  }
  static_routes = [
    { route_table = "cde", cidr = "10.110.0.0/16" },
    { route_table = "cde", cidr = "0.0.0.0/0", attachment = "egress" },
  ]
  ram_principals = ["arn:aws:organizations::222222222222:organization/o-abc123def4"]
  tags = {
    environment = "prod", team = "platform", owner = "platform@example.com", cost-center = "cc-100", cell = "shared"
    component   = "tgw", pci-scope = "connected", data-class = "internal", backup-tier = "none", managed-by = "terraform", repo = "infra/modules/transit-gateway"
  }
}

run "no_default_route_tables" {
  command = plan

  assert {
    condition     = aws_ec2_transit_gateway.this.default_route_table_association == "disable" && aws_ec2_transit_gateway.this.default_route_table_propagation == "disable"
    error_message = "routing is explicit"
  }
  assert {
    condition     = aws_ec2_transit_gateway.this.auto_accept_shared_attachments == "disable"
    error_message = "shared attachments need approval"
  }
}

run "attachments_routes_and_sharing" {
  command = plan

  assert {
    condition     = length(aws_ec2_transit_gateway_vpc_attachment.this) == 2 && length(aws_ec2_transit_gateway_route_table_association.this) == 2
    error_message = "each attachment is associated once"
  }
  assert {
    condition     = length(aws_ec2_transit_gateway_route_table_propagation.this) == 2
    error_message = "propagations follow propagate_to"
  }
  assert {
    condition     = aws_ec2_transit_gateway_route.this["cde/10.110.0.0/16"].blackhole && !aws_ec2_transit_gateway_route.this["cde/0.0.0.0/0"].blackhole
    error_message = "CDE to platform is a blackhole, egress is a real route"
  }
  assert {
    condition     = aws_ec2_transit_gateway_vpc_attachment.this["egress"].appliance_mode_support == "enable"
    error_message = "the egress attachment is an appliance attachment"
  }
  assert {
    condition     = length(aws_ram_principal_association.this) == 1
    error_message = "shared with the organization"
  }
}

run "unknown_route_table_rejected" {
  command = plan

  variables {
    attachments = {
      x = { vpc_id = "vpc-1", subnet_ids = ["s-1"], route_table = "nope" }
    }
    static_routes  = []
    ram_principals = []
  }

  expect_failures = [var.attachments]
}
