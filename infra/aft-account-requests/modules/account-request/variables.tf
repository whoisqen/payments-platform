variable "name" {
  type        = string
  description = "Account name in lower-case kebab-case, for example cde-prod."

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.name))
    error_message = "name must be lower-case kebab-case."
  }
}

variable "email" {
  type        = string
  description = "Unique root e-mail of the account (a group alias, never a person)."

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[a-z]{2,}$", var.email))
    error_message = "email must be an e-mail address."
  }
}

variable "ou" {
  type        = string
  description = "Control Tower organizational unit of the OU table in section 3."

  validation {
    condition     = contains(["Infrastructure", "Workloads/CDE", "Workloads/NonCDE", "Sandbox"], var.ou)
    error_message = "ou must be Infrastructure, Workloads/CDE, Workloads/NonCDE or Sandbox."
  }
}

variable "sso_user" {
  type = object({
    email      = string
    first_name = string
    last_name  = string
  })
  description = "Initial IAM Identity Center user that Control Tower creates; people get access later through groups."
}

variable "account_customizations_name" {
  type        = string
  description = "Folder in the AFT account-customizations repository."
}

variable "change_reason" {
  type        = string
  default     = "account request from infra/aft-account-requests"
  description = "Reason recorded in the AFT request."
}

variable "request_table_name" {
  type        = string
  default     = "aft-request"
  description = "DynamoDB table of the AFT management account."
}

variable "tags" {
  type        = map(string)
  description = "Account tags of section 22 (environment, team, owner, cost-center, cell, pci-scope, data-class, backup-tier, managed-by)."

  validation {
    condition     = alltrue([for k in ["environment", "team", "owner", "cost-center", "cell", "pci-scope", "data-class", "backup-tier", "managed-by"] : contains(keys(var.tags), k)])
    error_message = "tags must hold environment, team, owner, cost-center, cell, pci-scope, data-class, backup-tier and managed-by."
  }

  validation {
    condition     = (var.ou == "Workloads/CDE") == (lookup(var.tags, "pci-scope", "") == "cde")
    error_message = "pci-scope = cde belongs to the Workloads/CDE OU and only to it."
  }
}
