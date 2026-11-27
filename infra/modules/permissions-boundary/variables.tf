variable "account_id" {
  type        = string
  description = "Account that holds the boundary; every workload, cluster and CI role of it attaches the policy."

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be 12 digits."
  }
}

variable "policy_name" {
  type        = string
  default     = "workload-boundary"
  description = "Name the env.hcl files build permissions_boundary_arn from (arn:aws:iam::<account>:policy/workload-boundary)."
}

variable "tags" {
  type        = map(string)
  description = "Tags of section 22; team, owner, pci-scope, data-class and backup-tier are required."

  validation {
    condition     = alltrue([for k in ["team", "owner", "pci-scope", "data-class", "backup-tier"] : contains(keys(var.tags), k)])
    error_message = "tags must contain team, owner, pci-scope, data-class and backup-tier."
  }
}
