variable "region" {
  type        = string
  description = "Region of the provider this module instance runs in."

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.region))
    error_message = "region must be an AWS region name such as eu-west-1."
  }
}

variable "environment" {
  type        = string
  description = "dev, stage or prod."

  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "environment must be dev, stage or prod."
  }
}

variable "component" {
  type        = string
  default     = "tgw-spoke"
  description = "Last part of the resource name."
}

variable "transit_gateway_id" {
  type        = string
  description = "Transit gateway of this environment and region (transit-gateway output transit_gateway_id)."
}

variable "peering_attachment_id" {
  type        = string
  description = "Peering attachment the hub requested for this spoke (transit-gateway-hub output peering_attachment_ids[<env>-<region-short>])."
}

variable "workload_route_table_id" {
  type        = string
  description = "Route table of the workload VPC attachment (cde); it gets hub_cidrs through the peering."
}

variable "workload_attachment_id" {
  type        = string
  description = "VPC attachment of the workload VPC, the only target of the peering route table."
}

variable "vpc_cidrs" {
  type        = list(string)
  description = "CIDRs of this environment's workload VPC in this region; the hub may reach only these."

  validation {
    condition     = length(var.vpc_cidrs) > 0 && alltrue([for c in var.vpc_cidrs : can(cidrhost(c, 0))])
    error_message = "vpc_cidrs must hold at least one valid IPv4 CIDR."
  }
}

variable "hub_cidrs" {
  type        = list(string)
  description = "Destinations in shared-services: the private tier of the central cluster and its internal NLBs."

  validation {
    condition     = length(var.hub_cidrs) > 0 && alltrue([for c in var.hub_cidrs : can(cidrhost(c, 0))])
    error_message = "hub_cidrs must hold at least one valid IPv4 CIDR."
  }
}

variable "admin_zone_id" {
  type        = string
  default     = null
  description = "Private zone of the admin tools in shared-services (admin-edge output zone_id); associated with vpc_id after admin-edge authorized it. Null skips it."
}

variable "vpc_id" {
  type        = string
  default     = null
  description = "Workload VPC that resolves the admin zone; required with admin_zone_id."
}

variable "tags" {
  type        = map(string)
  description = "Tags of section 22; team, owner, pci-scope, data-class and backup-tier are required."

  validation {
    condition     = alltrue([for k in ["team", "owner", "pci-scope", "data-class", "backup-tier"] : contains(keys(var.tags), k)])
    error_message = "tags must contain team, owner, pci-scope, data-class and backup-tier."
  }
}

variable "name_prefix" {
  type        = string
  description = "Prefix of every resource name; set from config/platform.yaml (naming.prefix)."

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,10}$", var.name_prefix))
    error_message = "name_prefix must be 2 to 11 lower-case letters or digits, starting with a letter."
  }
}
