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
  description = "State root (directory under infra/live) whose stacks run as this role."

  validation {
    condition     = contains(["dev", "stage", "prod", "management", "security", "shared-services"], var.environment)
    error_message = "environment must be dev, stage, prod, management, security or shared-services."
  }
}

variable "shared_services_account_id" {
  type        = string
  description = "Account of the CI roles (plan and component apply roles of this root)."

  validation {
    condition     = can(regex("^[0-9]{12}$", var.shared_services_account_id))
    error_message = "shared_services_account_id must be 12 digits."
  }
}

variable "permissions_boundary_arn" {
  type        = string
  default     = null
  description = "Boundary of the role; null (the live units) because modules create service roles without workload-boundary and the boundary policy itself is applied through this role. The SCPs are the limit."
}

variable "tags" {
  type        = map(string)
  description = "Tags of section 22; team, owner, pci-scope, data-class and backup-tier are required."

  validation {
    condition     = alltrue([for k in ["team", "owner", "pci-scope", "data-class", "backup-tier"] : contains(keys(var.tags), k)])
    error_message = "tags must contain team, owner, pci-scope, data-class and backup-tier."
  }
}
