variable "name_prefix" {
  type        = string
  description = "Prefix of every resource name; set from config/platform.yaml (naming.prefix)."

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,10}$", var.name_prefix))
    error_message = "name_prefix must be 2 to 11 lower-case letters or digits, starting with a letter."
  }
}

variable "host" {
  type        = string
  description = "Host of central.logs_otlp_endpoint, without scheme and port; the certificate subject and the DNS name."

  validation {
    condition     = can(regex("^([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)+[a-z]{2,}$", var.host))
    error_message = "host must be a lower-case DNS name."
  }
}

variable "certificate_authority_arn" {
  type        = string
  description = "AWS Private CA of shared-services (admin-edge output ca_arn); it signs the server certificate and the collector client certificates."
}

variable "ca_key_algorithm" {
  type        = string
  default     = "EC_prime256v1"
  description = "Key algorithm of the private CA (admin-edge ca_key_algorithm); picks the signing algorithm."
}

variable "validity_days" {
  type        = number
  default     = 365
  description = "Validity of the server certificate."
}

variable "rotation_days" {
  type        = number
  default     = 300
  description = "Age after which the next apply issues a new key and certificate; must stay below validity_days."

  validation {
    condition     = var.rotation_days >= 30
    error_message = "rotation_days must be at least 30."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "Key of the secret (the shared key of shared-services)."
}

variable "vpc_ids" {
  type        = list(string)
  description = "VPCs that resolve the host through the private zone."

  validation {
    condition     = length(var.vpc_ids) > 0
    error_message = "give at least one VPC id."
  }
}

variable "nlb_lookup_enabled" {
  type        = bool
  default     = false
  description = "Second step of the apply: true looks up the internal NLB of the logs Gateway and adds the alias record."
}

variable "nlb_stack_tag" {
  type        = string
  default     = "monitoring/logs"
  description = "Tag service.k8s.aws/stack of the NLB that the load balancer controller builds for the logs Gateway (namespace/service)."

  validation {
    condition     = can(regex("^[a-z0-9-]+/[a-z0-9.-]+$", var.nlb_stack_tag))
    error_message = "nlb_stack_tag must look like namespace/name."
  }
}

variable "tags" {
  type        = map(string)
  description = "Section 22 tags that Terragrunt default_tags do not set: team, owner, pci-scope, data-class, backup-tier."

  validation {
    condition     = alltrue([for k in ["team", "owner", "pci-scope", "data-class", "backup-tier"] : contains(keys(var.tags), k)])
    error_message = "tags must contain team, owner, pci-scope, data-class and backup-tier."
  }
}
