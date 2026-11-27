variable "name_prefix" {
  type        = string
  description = "Prefix of every resource name; naming.prefix of config/platform.yaml."

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,10}$", var.name_prefix))
    error_message = "name_prefix must be 2 to 11 lower-case letters or digits, starting with a letter."
  }
}

variable "github_repository" {
  type        = string
  description = "owner/name of the repository whose workflow runs the revocation apply."

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must be owner/name."
  }
}

variable "workflow_file" {
  type        = string
  default     = "cde-jit-revocation.yml"
  description = "Workflow (workflow_dispatch on main) that applies identity-center with CDE_JIT_REVOCATION_RUN=true."
}

variable "schedule_expression" {
  type        = string
  default     = "rate(15 minutes)"
  description = "How often expired CDE grants are revoked; the README of identity-center promises 15 minutes."
}

variable "tags" {
  type        = map(string)
  description = "Tags of section 22; team, owner, pci-scope, data-class and backup-tier are required."

  validation {
    condition     = alltrue([for k in ["team", "owner", "pci-scope", "data-class", "backup-tier"] : contains(keys(var.tags), k)])
    error_message = "tags must contain team, owner, pci-scope, data-class and backup-tier."
  }
}
