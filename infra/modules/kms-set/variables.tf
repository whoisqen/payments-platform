variable "account_id" {
  type        = string
  description = "AWS account that owns the keys."
  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be 12 digits."
  }
}

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

variable "keys" {
  type = map(object({
    service_principals = optional(list(string), [])
    admin_role_arns    = optional(list(string), [])
    user_role_arns     = optional(list(string), [])
  }))
  description = "Keys by purpose (the kms component); one stack holds every key of a region so that a replica set mirrors the primary set."
}

variable "is_replica" {
  type        = bool
  default     = false
  description = "Create replicas of primary_key_arns in this recovery region instead of primaries."
}

variable "primary_key_arns" {
  type        = map(string)
  default     = {}
  description = "Primary key ARN by purpose; required for every key when is_replica is true."
  validation {
    condition     = !var.is_replica || alltrue([for k in keys(var.keys) : contains(keys(var.primary_key_arns), k)])
    error_message = "primary_key_arns must hold an ARN for every key of a replica set."
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
