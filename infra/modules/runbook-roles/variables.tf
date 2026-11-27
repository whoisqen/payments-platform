variable "name_prefix" {
  type        = string
  description = "Prefix of every resource name; naming.prefix of config/platform.yaml."

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,10}$", var.name_prefix))
    error_message = "name_prefix must be 2 to 11 lower-case letters or digits, starting with a letter."
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

variable "account_id" {
  type        = string
  description = "Account of the environment; the roles and documents live here."

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be 12 digits."
  }
}

variable "github_repository" {
  type        = string
  description = "owner/name of the repository whose runbook workflows assume the roles."
}

variable "regions" {
  type        = list(string)
  description = "Regions where the pay-runbook-* documents run."
}

variable "actions_exec_policy_arns" {
  type        = list(string)
  default     = []
  description = "Policies of the documents' write steps, attached to the -actions-exec role; the diagnose roles stay read-only."
}

variable "permissions_boundary_arn" {
  type        = string
  description = "workload-boundary of the account."
}

variable "tags" {
  type        = map(string)
  description = "Tags of section 22; team, owner, pci-scope, data-class and backup-tier are required."

  validation {
    condition     = alltrue([for k in ["team", "owner", "pci-scope", "data-class", "backup-tier"] : contains(keys(var.tags), k)])
    error_message = "tags must contain team, owner, pci-scope, data-class and backup-tier."
  }
}
