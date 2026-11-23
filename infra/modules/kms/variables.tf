variable "account_id" {
  type        = string
  description = "AWS account that owns the key."

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

variable "component" {
  type        = string
  description = "Key purpose, the last part of the alias and the resource name."
}

variable "is_replica" {
  type        = bool
  default     = false
  description = "Create a replica of primary_key_arn instead of a primary; a flag of its own because the ARN is unknown at plan time in the same apply."
}

variable "primary_key_arn" {
  type        = string
  default     = null
  description = "ARN of the multi-Region primary key; required when is_replica is true."

  validation {
    condition     = var.is_replica == (var.primary_key_arn != null)
    error_message = "primary_key_arn must be set exactly when is_replica is true."
  }
}

variable "multi_region" {
  type        = bool
  default     = true
  description = "Create the primary as a multi-Region key so that recovery regions can hold replicas."
}

variable "admin_role_arns" {
  type        = list(string)
  default     = []
  description = "Roles that manage the key but cannot use it for crypto operations."
}

variable "user_role_arns" {
  type        = list(string)
  default     = []
  description = "Roles that may encrypt, decrypt and create grants."
}

variable "service_principals" {
  type        = list(string)
  default     = []
  description = "AWS services (for example logs.amazonaws.com) allowed to use the key through the account."
}

variable "deletion_window_in_days" {
  type        = number
  default     = 30
  description = "Waiting period before a scheduled deletion takes effect."
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
