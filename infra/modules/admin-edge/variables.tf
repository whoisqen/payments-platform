variable "name_prefix" {
  type        = string
  description = "Prefix of resource names; set from config/platform.yaml (naming.prefix)."

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,10}$", var.name_prefix))
    error_message = "name_prefix must be 2 to 11 lower-case letters or digits, starting with a letter."
  }
}

variable "environment" {
  type        = string
  default     = "shared-services"
  description = "Environment segment of resource names; the admin tools run in the shared-services account."

  validation {
    condition     = var.environment == "shared-services"
    error_message = "the admin tools belong to the shared-services account."
  }
}

variable "zone_name" {
  type        = string
  description = "Private zone of the admin tools (config/platform.yaml, dns.admin_zone), for example payments.internal."

  validation {
    condition     = can(regex("^([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)+[a-z]{2,}$", var.zone_name))
    error_message = "zone_name must be a lower-case DNS name with at least two labels."
  }
}

variable "vpc_ids" {
  type        = list(string)
  description = "VPCs that resolve the zone: the VPC of the central cluster and the VPCs of the administrators' access path."

  validation {
    condition     = length(var.vpc_ids) > 0 && length(distinct(var.vpc_ids)) == length(var.vpc_ids)
    error_message = "give at least one VPC id, without duplicates."
  }
}

variable "nlb_lookup_enabled" {
  type        = bool
  default     = false
  description = "Second step of the apply: false creates the zone, the CA and the roles only; true looks up the internal NLB that the AWS Load Balancer Controller built from the Gateway and adds the wildcard alias record."
}

variable "nlb_stack_tag" {
  type        = string
  default     = null
  description = "Value of the tag service.k8s.aws/stack of the NLB, namespace/gateway-name of the internal Gateway. Required when nlb_lookup_enabled is true."

  validation {
    condition     = var.nlb_stack_tag == null || can(regex("^[a-z0-9-]+/[a-z0-9.-]+$", var.nlb_stack_tag))
    error_message = "nlb_stack_tag must look like namespace/name."
  }
}

variable "cluster_name" {
  type        = string
  description = "Central EKS cluster that runs the controllers; the load balancer controller policy is scoped to resources tagged with it."
}

variable "permissions_boundary_arn" {
  type        = string
  description = "Boundary policy of policy/iam/boundaries attached to every role."
}

variable "load_balancer_controller" {
  type = object({
    namespace       = optional(string, "kube-system")
    service_account = optional(string, "aws-load-balancer-controller")
  })
  default     = {}
  description = "Service account that gets the role of the AWS Load Balancer Controller."
}

variable "privateca_issuer" {
  type = object({
    namespace       = optional(string, "cert-manager")
    service_account = optional(string, "aws-privateca-issuer")
  })
  default     = {}
  description = "Service account that gets the role of the AWS Private CA issuer for cert-manager."
}

variable "ca_organization" {
  type        = string
  description = "Organization in the subject of the root CA."
}

variable "ca_key_algorithm" {
  type        = string
  default     = "EC_prime256v1"
  description = "Key algorithm of the root CA."

  validation {
    condition     = contains(["RSA_2048", "RSA_4096", "EC_prime256v1", "EC_secp384r1"], var.ca_key_algorithm)
    error_message = "ca_key_algorithm must be RSA_2048, RSA_4096, EC_prime256v1 or EC_secp384r1."
  }
}

variable "ca_validity_years" {
  type        = number
  default     = 10
  description = "Years the root CA certificate is valid."

  validation {
    condition     = var.ca_validity_years >= 1 && var.ca_validity_years <= 20
    error_message = "ca_validity_years must be between 1 and 20."
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
