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
  description = "Name segment of the group of stores, for example data-cell-0 or data-locker."
}

variable "vpc_id" {
  type        = string
  description = "VPC of the stores."
}

variable "data_subnet_ids" {
  type        = list(string)
  description = "Data subnets, one per AZ, for the Aurora DB subnet group."
  validation {
    condition     = length(var.data_subnet_ids) == 3
    error_message = "data_subnet_ids must list one subnet in each of three AZs."
  }
}

variable "stores" {
  type = map(object({
    port    = number
    clients = string
  }))
  description = "Security group per store with its port; clients is workload (the client lists below) or the name of another store that is the only source."
  validation {
    condition     = alltrue([for s in var.stores : s.clients == "workload" || contains(keys(var.stores), s.clients)])
    error_message = "clients must be workload or the name of a store in this map."
  }
}

variable "client_security_group_ids" {
  type        = list(string)
  default     = []
  description = "Node security groups of the clusters whose pods may reach the workload-facing stores."
}

variable "client_cidr_blocks" {
  type        = list(string)
  default     = []
  description = "CIDRs allowed as clients, empty in the CDE; a recovery region leaves both client lists empty until the switch."
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
  description = "Prefix of every resource name, for example the project short name; set from config/platform.yaml (naming.prefix)."

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,10}$", var.name_prefix))
    error_message = "name_prefix must be 2 to 11 lower-case letters or digits, starting with a letter."
  }
}
