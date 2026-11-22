mock_provider "aws" {}

variables {
  region               = "eu-central-1"
  environment          = "prod"
  component            = "vpc-cde"
  cidr_block           = "10.100.0.0/16"
  azs                  = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
  flow_logs_bucket_arn = "arn:aws:s3:::pay-prod-euc1-flow-logs"
  subnet_cidrs = {
    public  = ["10.100.0.0/24", "10.100.1.0/24", "10.100.2.0/24"]
    private = ["10.100.32.0/19", "10.100.64.0/19", "10.100.96.0/19"]
    data    = ["10.100.10.0/24", "10.100.11.0/24", "10.100.12.0/24"]
  }
  tags = {
    environment = "prod", team = "platform", owner = "platform@example.com", cost-center = "cc-100", cell = "shared"
    component   = "vpc", pci-scope = "cde", data-class = "card-data", backup-tier = "none", managed-by = "terraform", repo = "infra/modules/vpc"
  }
}

run "three_azs_three_tiers" {
  command = plan

  assert {
    condition     = length(aws_subnet.this) == 9
    error_message = "three tiers in three AZs"
  }
  assert {
    condition     = length(aws_route_table.private) == 3 && length(aws_route_table.data) == 3
    error_message = "one private and one data route table per AZ"
  }
  assert {
    condition     = aws_vpc.this.tags["Name"] == "pay-prod-euc1-vpc-cde"
    error_message = "name follows pay-<env>-<region-short>-<component>"
  }
}

run "cde_has_no_internet_gateway_and_no_default_route" {
  command = plan

  assert {
    condition     = length(aws_internet_gateway.this) == 0 && length(aws_route.public_internet) == 0 && length(aws_route.private_egress) == 0
    error_message = "no internet gateway and no default route without a transit gateway"
  }
}

run "endpoints_include_s3_and_ecr" {
  command = plan

  assert {
    condition     = contains(keys(aws_vpc_endpoint.gateway), "s3") && contains(keys(aws_vpc_endpoint.interface), "ecr.api") && contains(keys(aws_vpc_endpoint.interface), "ecr.dkr")
    error_message = "S3 gateway endpoint and ECR interface endpoints are required"
  }
  assert {
    condition     = alltrue([for e in aws_vpc_endpoint.interface : e.private_dns_enabled])
    error_message = "interface endpoints use private DNS"
  }
}

run "flow_logs_to_s3" {
  command = plan

  assert {
    condition     = aws_flow_log.this.log_destination_type == "s3" && aws_flow_log.this.traffic_type == "ALL"
    error_message = "all traffic goes to S3"
  }
}

run "egress_through_transit_gateway" {
  command = plan

  variables {
    enable_egress_route       = true
    egress_transit_gateway_id = "tgw-0123456789abcdef0"
  }

  assert {
    condition     = length(aws_route.private_egress) == 3
    error_message = "every private route table gets the egress route"
  }
}

run "recovery_region_without_public_tier" {
  command = plan

  variables {
    region     = "us-east-1"
    cidr_block = "10.102.0.0/16"
    azs        = ["us-east-1a", "us-east-1b", "us-east-1c"]
    subnet_cidrs = {
      private = ["10.102.32.0/19", "10.102.64.0/19", "10.102.96.0/19"]
      data    = ["10.102.10.0/24", "10.102.11.0/24", "10.102.12.0/24"]
    }
  }

  assert {
    condition     = length(aws_subnet.this) == 6 && length(aws_route_table.public) == 0
    error_message = "no public tier"
  }
  assert {
    condition     = aws_vpc.this.tags["Name"] == "pay-prod-use1-vpc-cde"
    error_message = "recovery region short name"
  }
}
