variable "region" {
  type        = string
  description = "Region of the provider this module instance runs in."

  validation {
    condition     = contains(["eu-central-1", "us-east-1", "us-east-2"], var.region)
    error_message = "region must be eu-central-1, us-east-1 or us-east-2."
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
  default     = "tgw"
  description = "Last part of the resource name."
}

variable "amazon_side_asn" {
  type        = number
  default     = 64512
  description = "Private ASN of the transit gateway."
}

variable "route_tables" {
  type        = list(string)
  description = "Route table names, for example cde, platform, egress and inspection."
}

variable "attachments" {
  type = map(object({
    vpc_id         = string
    subnet_ids     = list(string)
    route_table    = string
    propagate_to   = optional(list(string), [])
    appliance_mode = optional(bool, false)
  }))
  default     = {}
  description = "VPC attachments by name; each is associated with one route table and propagates to the listed ones."

  validation {
    condition     = alltrue([for a in var.attachments : contains(var.route_tables, a.route_table) && alltrue([for rt in a.propagate_to : contains(var.route_tables, rt)])])
    error_message = "route_table and propagate_to must name entries of route_tables."
  }
}

variable "static_routes" {
  type = list(object({
    route_table = string
    cidr        = string
    attachment  = optional(string)
  }))
  default     = []
  description = "Static routes; a null attachment makes a blackhole route (for example CDE to platform)."

  validation {
    condition     = alltrue([for r in var.static_routes : contains(var.route_tables, r.route_table) && (r.attachment == null || contains(keys(var.attachments), r.attachment))])
    error_message = "static route names must exist in route_tables and attachments."
  }
}

variable "ram_principals" {
  type        = list(string)
  default     = []
  description = "Organization or OU ARNs the transit gateway is shared with through AWS RAM."
}

variable "tags" {
  type        = map(string)
  description = "Tags of section 22; team, owner, pci-scope, data-class and backup-tier are required."

  validation {
    condition     = alltrue([for k in ["team", "owner", "pci-scope", "data-class", "backup-tier"] : contains(keys(var.tags), k)])
    error_message = "tags must contain team, owner, pci-scope, data-class and backup-tier."
  }
}
