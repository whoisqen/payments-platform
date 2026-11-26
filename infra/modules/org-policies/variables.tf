variable "name_prefix" {
  description = "Prefix of every policy name."
  type        = string
  default     = "pay"
}

variable "policy_dir" {
  description = "Directory of the policy documents: *.json are SCPs, tag-policies/*.json tag policies, backup-policies/*.json backup policies."
  type        = string
}

variable "target_ids" {
  description = "Organization root and OU ids keyed by a short name (root, security, infrastructure, workloads_cde, workloads_noncde, sandbox)."
  type        = map(string)

  validation {
    condition     = alltrue([for id in values(var.target_ids) : can(regex("^(r-[0-9a-z]{4,32}|ou-[0-9a-z]{4,32}-[a-z0-9]{8,32}|[0-9]{12})$", id))])
    error_message = "target_ids values must be a root id (r-...), an OU id (ou-...-...) or an account id."
  }
}

variable "policy_targets" {
  description = "Targets of each policy document, keyed by file name without .json; values are keys of target_ids. Every document needs an entry."
  type        = map(list(string))
}

variable "organization_id" {
  description = "Organization id (o-...) that the resource control policy trusts."
  type        = string

  validation {
    condition     = can(regex("^o-[a-z0-9]{10,32}$", var.organization_id))
    error_message = "organization_id must look like o-abcdefghij."
  }
}

variable "rcp_targets" {
  description = "Keys of target_ids that get the resource control policy denying S3, KMS and Secrets Manager access from outside the organization; empty skips it."
  type        = list(string)
  default     = ["workloads_cde"]
}

variable "rcp_actions" {
  description = "Services guarded by the resource control policy."
  type        = list(string)
  default     = ["s3:*", "kms:*", "secretsmanager:*"]
}

variable "tags" {
  description = "Section 22 tags that Terragrunt default_tags do not set: team, owner, pci-scope, data-class, backup-tier."
  type        = map(string)

  validation {
    condition     = alltrue([for k in ["team", "owner", "pci-scope", "data-class", "backup-tier"] : contains(keys(var.tags), k)])
    error_message = "tags must contain team, owner, pci-scope, data-class and backup-tier."
  }

  validation {
    condition = (
      contains(["payments-core", "platform", "security", "data"], lookup(var.tags, "team", "")) &&
      contains(["cde", "connected", "out-of-scope"], lookup(var.tags, "pci-scope", "")) &&
      contains(["card-data", "pii", "internal", "public"], lookup(var.tags, "data-class", "")) &&
      contains(["gold", "silver", "bronze", "none"], lookup(var.tags, "backup-tier", ""))
    )
    error_message = "tags team, pci-scope, data-class or backup-tier is outside the section 22.1 schema."
  }
}
