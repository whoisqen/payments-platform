variable "name_prefix" {
  type        = string
  description = "Prefix of every resource name; set from config/platform.yaml (naming.prefix)."

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,10}$", var.name_prefix))
    error_message = "name_prefix must be 2 to 11 lower-case letters or digits, starting with a letter."
  }
}

variable "environment" {
  type        = string
  default     = "shared-services"
  description = "Environment segment of the names; the central observability stack lives in the shared-services account."

  validation {
    condition     = var.environment == "shared-services"
    error_message = "the observability stores belong to the shared-services account."
  }
}

variable "region_short" {
  type        = string
  description = "Short region code of the provider region, for example euc1 (bucket pay-shared-services-euc1-loki)."

  validation {
    condition     = can(regex("^[a-z]{2,3}[0-9]$", var.region_short))
    error_message = "region_short must look like euc1 or use1."
  }
}

variable "cluster_name" {
  type        = string
  description = "Name of the central cluster (eks module); the Pod Identity associations are created in it."
}

variable "kms_key_arn" {
  type        = string
  description = "Customer managed key of the buckets (the shared key of the kms stack)."
}

variable "permissions_boundary_arn" {
  type        = string
  description = "Boundary policy of policy/iam/boundaries attached to every role."
}

variable "buckets" {
  type = map(object({
    retention_days  = number
    namespace       = string
    service_account = string
  }))
  description = "Stores by component: days until objects expire, and the service account that gets the one role of the bucket."
  default = {
    loki   = { retention_days = 30, namespace = "monitoring", service_account = "loki" }
    tempo  = { retention_days = 14, namespace = "monitoring", service_account = "tempo" }
    sentry = { retention_days = 90, namespace = "monitoring", service_account = "sentry" }
  }

  validation {
    condition     = alltrue([for b in values(var.buckets) : b.retention_days >= 1])
    error_message = "retention_days must be at least 1."
  }
}

variable "noncurrent_retention_days" {
  type        = number
  default     = 7
  description = "Days a replaced or deleted version stays recoverable (versioning is on)."
}

variable "tags" {
  type        = map(string)
  description = "Section 22 tags that Terragrunt default_tags do not set: team, owner, pci-scope, data-class, backup-tier."

  validation {
    condition     = alltrue([for k in ["team", "owner", "pci-scope", "data-class", "backup-tier"] : contains(keys(var.tags), k)])
    error_message = "tags must contain team, owner, pci-scope, data-class and backup-tier."
  }
}
