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
  description = "prod, the only environment with a standby region."

  validation {
    condition     = var.environment == "prod"
    error_message = "environment must be prod."
  }
}

variable "region" {
  type        = string
  description = "Standby region of the provider."

  validation {
    condition     = var.region == "us-east-1"
    error_message = "region must be us-east-1, the standby region."
  }
}

variable "host_cluster" {
  type = object({
    name              = string
    oidc_provider_arn = string
    oidc_issuer       = string
  })
  description = "First standby cell cluster that runs Argo CD core; oidc_issuer is without https://."
}

variable "clusters" {
  type        = map(string)
  description = "Cell => EKS cluster name of every standby cluster Argo CD manages, the host included."

  validation {
    condition     = length(var.clusters) > 0
    error_message = "clusters must name at least the host cluster."
  }
}

variable "namespace" {
  type        = string
  default     = "argocd"
  description = "Namespace of the Argo CD release in the host cluster."
}

variable "controller_service_accounts" {
  type        = list(string)
  default     = ["argocd-application-controller"]
  description = "Service accounts that receive the controller role through IRSA (annotation eks.amazonaws.com/role-arn)."
}

variable "managed_namespaces" {
  type        = list(string)
  description = "Namespaces the controller may administer in every cluster; the same scope as the argocd entry of env.hcl."

  validation {
    condition     = length(var.managed_namespaces) > 0
    error_message = "the controller needs a namespaced scope."
  }
}

variable "installer_role_arn" {
  type        = string
  default     = null
  description = "Role that installs Argo CD (CRDs, cluster roles) into the host cluster at the switch; null grants nothing. Set it only for the install and apply again without it."

  validation {
    condition     = var.installer_role_arn == null || can(regex("^arn:aws:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]+$", var.installer_role_arn))
    error_message = "installer_role_arn must be an IAM role ARN."
  }
}

variable "permissions_boundary_arn" {
  type        = string
  description = "Boundary attached to the controller role."
}

variable "tags" {
  type        = map(string)
  description = "Tags of section 22; team, owner, pci-scope, data-class and backup-tier are required."

  validation {
    condition     = alltrue([for k in ["team", "owner", "pci-scope", "data-class", "backup-tier"] : contains(keys(var.tags), k)])
    error_message = "tags must contain team, owner, pci-scope, data-class and backup-tier."
  }
}
