variable "account_id" {
  type        = string
  description = "shared-services account that holds the state bucket."

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be 12 digits."
  }
}

variable "environment" {
  type        = string
  default     = "prod"
  description = "Environment whose state this bucket holds; state keys start with it."

  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "environment must be dev, stage or prod."
  }
}

variable "github_repository" {
  type        = string
  description = "owner/name of the repository whose workflows may assume the CI roles."
}

variable "permissions_boundary_arn" {
  type        = string
  description = "Boundary policy for the CI roles; it must exist before the first apply (created by the iam-baseline stack or by hand)."
}

variable "apply_roles" {
  type = map(object({
    github_environment = string
    actions            = list(string)
    resource_arns      = list(string)
    unscoped_actions   = optional(list(string), [])
  }))
  default     = {}
  description = "Apply roles per component; empty on the first run, the components add theirs later."
}

variable "state_retention_days" {
  type        = number
  default     = 365
  description = "Governance retention of state versions (backup-tier gold, section 9)."
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
