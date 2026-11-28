variable "region" {
  type        = string
  description = "Region of the hub transit gateway."

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.region))
    error_message = "region must be an AWS region name such as eu-west-1."
  }
}

variable "environment" {
  type        = string
  default     = "shared-services"
  description = "Environment segment of resource names; the hub lives in shared-services."
}

variable "component" {
  type        = string
  default     = "tgw-hub"
  description = "Last part of the resource name."
}

variable "transit_gateway_id" {
  type        = string
  description = "Hub transit gateway (transit-gateway output transit_gateway_id of shared-services)."
}

variable "hub_route_table_id" {
  type        = string
  description = "Route table of the shared-services VPC attachment; it gets each spoke's CIDRs through that spoke's peering."
}

variable "hub_attachment_id" {
  type        = string
  description = "VPC attachment of the shared-services VPC, the only target of the spoke route tables."
}

variable "hub_cidrs" {
  type        = list(string)
  description = "Destinations in shared-services that spokes may reach: the private tier of the central cluster and its internal NLBs, never the untrusted runner tier."

  validation {
    condition     = length(var.hub_cidrs) > 0 && alltrue([for c in var.hub_cidrs : can(cidrhost(c, 0))])
    error_message = "hub_cidrs must hold at least one valid IPv4 CIDR."
  }
}

variable "spokes" {
  type = map(object({
    account_id         = string
    region             = string
    transit_gateway_id = string
    cidrs              = list(string)
    accepted           = optional(bool, false)
  }))
  description = "Environment transit gateways by name (<env>-<region-short>); accepted turns on the association and routes once the spoke account accepted the peering."

  validation {
    condition     = alltrue([for s in var.spokes : can(regex("^[0-9]{12}$", s.account_id)) && length(s.cidrs) > 0 && alltrue([for c in s.cidrs : can(cidrhost(c, 0))])])
    error_message = "every spoke needs a 12-digit account_id and at least one valid IPv4 CIDR."
  }

  validation {
    condition = alltrue(flatten([
      for a in flatten([for k, s in var.spokes : [for c in s.cidrs : { spoke = k, cidr = c }]]) : [
        for b in flatten([for k, s in var.spokes : [for c in s.cidrs : { spoke = k, cidr = c }]]) :
        a.spoke == b.spoke || cidrsubnet("${cidrhost(a.cidr, 0)}/${min(tonumber(split("/", a.cidr)[1]), tonumber(split("/", b.cidr)[1]))}", 0, 0) != cidrsubnet("${cidrhost(b.cidr, 0)}/${min(tonumber(split("/", a.cidr)[1]), tonumber(split("/", b.cidr)[1]))}", 0, 0)
      ]
    ]))
    error_message = "spoke CIDRs must not overlap between spokes, or one spoke's route would carry another spoke's traffic."
  }
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
