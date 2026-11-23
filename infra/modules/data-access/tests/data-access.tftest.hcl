mock_provider "aws" {}

variables {
  name_prefix     = "pay"
  region          = "eu-central-1"
  environment     = "dev"
  component       = "data-cell-0"
  vpc_id          = "vpc-0abc"
  data_subnet_ids = ["subnet-a", "subnet-b", "subnet-c"]
  stores = {
    aurora       = { port = 5432, clients = "aurora-proxy" }
    aurora-proxy = { port = 5432, clients = "workload" }
    memorydb     = { port = 6379, clients = "workload" }
  }
  client_security_group_ids = ["sg-0node"]
  tags = {
    team = "payments-core", owner = "payments@example.com", pci-scope = "cde", data-class = "card-data", backup-tier = "gold"
  }
}

run "stores_admit_only_their_clients" {
  command = plan

  assert {
    condition     = length(aws_security_group.this) == 3
    error_message = "one group per store"
  }
  assert {
    condition     = aws_vpc_security_group_ingress_rule.this["memorydb/sg-0"].referenced_security_group_id == "sg-0node" && aws_vpc_security_group_ingress_rule.this["memorydb/sg-0"].from_port == 6379
    error_message = "MemoryDB admits the node group on 6379"
  }
  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.this) == 3
    error_message = "one rule per store and client"
  }
  assert {
    condition     = alltrue([for r in aws_vpc_security_group_ingress_rule.this : r.cidr_ipv4 == null])
    error_message = "no CIDR ingress in the CDE"
  }
}

run "aurora_is_reached_only_through_its_proxy" {
  command = plan

  assert {
    condition     = length(aws_vpc_security_group_egress_rule.to_store) == 1 && aws_vpc_security_group_egress_rule.to_store["aurora"].from_port == 5432
    error_message = "the proxy opens connections to Aurora only"
  }
}

run "recovery_region_has_no_clients" {
  command = plan

  variables {
    client_security_group_ids = []
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.this) == 1
    error_message = "only the proxy to Aurora rule exists"
  }
}

run "unknown_front_store_is_rejected" {
  command = plan

  variables {
    stores = {
      aurora = { port = 5432, clients = "missing" }
    }
  }

  expect_failures = [var.stores]
}
