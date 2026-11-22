variable "environment" {
  type        = string
  description = "dev, stage or prod."

  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "environment must be dev, stage or prod."
  }
}

variable "zone_name" {
  type        = string
  description = "Public hosted zone, for example pay.example.com."

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]*\\.[a-z]{2,}$", var.zone_name))
    error_message = "zone_name must be a lower-case domain name."
  }
}

variable "certificates" {
  type = map(object({
    domain_name               = string
    subject_alternative_names = optional(list(string), [])
  }))
  default     = {}
  description = "ACM certificates by name, validated through DNS in this zone; ACM renews them without action."
}

variable "caa_issuers" {
  type        = list(string)
  default     = ["amazon.com", "amazonaws.com", "amazontrust.com", "awstrust.com", "letsencrypt.org"]
  description = "CAs allowed to issue for the zone (ACM and Let's Encrypt for cert-manager)."
}

variable "enable_dnssec" {
  type        = bool
  default     = false
  description = "Sign the zone; a flag because the key ARN may be unknown at plan time."
}

variable "dnssec_kms_key_arn" {
  type        = string
  default     = null
  description = "Asymmetric ECC_NIST_P256 key in us-east-1 for the key-signing key."

  validation {
    condition     = !var.enable_dnssec || var.dnssec_kms_key_arn != null
    error_message = "dnssec_kms_key_arn is required when enable_dnssec is true."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags of section 22; team, owner, pci-scope, data-class and backup-tier are required."

  validation {
    condition     = alltrue([for k in ["team", "owner", "pci-scope", "data-class", "backup-tier"] : contains(keys(var.tags), k)])
    error_message = "tags must contain team, owner, pci-scope, data-class and backup-tier."
  }
}
