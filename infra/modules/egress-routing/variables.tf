variable "azs" {
  type        = list(string)
  description = "The three availability zones of the egress VPC; every per-AZ list below is ordered like it."

  validation {
    condition     = length(var.azs) == 3
    error_message = "azs must hold exactly three zones."
  }
}

variable "transit_gateway_id" {
  type        = string
  description = "Transit gateway that carries workload traffic to and from the egress VPC."
}

variable "workload_cidrs" {
  type        = list(string)
  description = "CIDRs of the workload VPCs behind the transit gateway; return traffic to them goes back through the firewall."

  validation {
    condition     = length(var.workload_cidrs) > 0 && alltrue([for c in var.workload_cidrs : can(cidrhost(c, 0)) && c != "0.0.0.0/0"])
    error_message = "workload_cidrs must be a non-empty list of CIDRs, never 0.0.0.0/0."
  }
}

variable "attachment_route_table_ids" {
  type        = list(string)
  description = "Route tables of the transit gateway attachment subnets, one per AZ (egress VPC data tier)."

  validation {
    condition     = length(var.attachment_route_table_ids) == 3
    error_message = "attachment_route_table_ids needs one route table per AZ."
  }
}

variable "firewall_route_table_ids" {
  type        = list(string)
  description = "Route tables of the firewall endpoint subnets, one per AZ (egress VPC private tier)."

  validation {
    condition     = length(var.firewall_route_table_ids) == 3
    error_message = "firewall_route_table_ids needs one route table per AZ."
  }
}

variable "nat_route_table_ids" {
  type        = list(string)
  description = "Route tables of the NAT gateway subnets, one per AZ (egress VPC public tier with public_route_table_per_az)."

  validation {
    condition     = length(distinct(var.nat_route_table_ids)) == 3
    error_message = "nat_route_table_ids needs three different route tables, one per AZ."
  }
}

variable "firewall_endpoint_ids" {
  type        = map(string)
  description = "Network Firewall endpoint per AZ name (network-firewall output firewall_endpoint_ids)."

  validation {
    condition     = alltrue([for az in var.azs : contains(keys(var.firewall_endpoint_ids), az)])
    error_message = "firewall_endpoint_ids needs an endpoint in every zone of azs."
  }
}

variable "nat_gateway_ids" {
  type        = list(string)
  description = "NAT gateways, one per AZ."

  validation {
    condition     = length(var.nat_gateway_ids) == 3
    error_message = "nat_gateway_ids needs one NAT gateway per AZ."
  }
}
