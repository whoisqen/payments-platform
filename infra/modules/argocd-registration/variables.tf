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
  description = "Environment of the cluster (dev, stage or prod)."

  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "environment must be dev, stage or prod."
  }
}

variable "cluster_region" {
  type        = string
  description = "Region of the cluster; the provider of this module runs in shared-services."
}

variable "argocd_cluster_name" {
  type        = string
  description = "eks output argocd_cluster_name: the destination name of the ApplicationSets and the secret name suffix."
}

variable "cluster_name" {
  type        = string
  description = "eks output cluster_name: the EKS name Argo CD signs its token for (awsAuthConfig.clusterName)."
}

variable "cluster_endpoint" {
  type        = string
  description = "eks output cluster_endpoint."
}

variable "certificate_authority_data" {
  type        = string
  description = "eks output certificate_authority_data (base64)."
}

variable "controller_role_arn" {
  type        = string
  description = "<prefix>-<env>-argocd-controller of the environment account (argocd-access spoke); Argo CD assumes it."
}

variable "reader_role_arn" {
  type        = string
  description = "The External Secrets role of the central cluster (<prefix>-shared-services-<region-short>-central-external-secrets); the only reader."
}

variable "writer_role_arn" {
  type        = string
  description = "<prefix>-shared-services-argocd-registration, the role this stack's provider assumes; kept able to read so that refresh works."
}

variable "kms_key_arn" {
  type        = string
  default     = null
  description = "Key of the secret; null uses aws/secretsmanager of shared-services, which the same-account reader may use."
}

variable "tags" {
  type        = map(string)
  description = "Tags of section 22; team, owner, pci-scope, data-class and backup-tier are required."

  validation {
    condition     = alltrue([for k in ["team", "owner", "pci-scope", "data-class", "backup-tier"] : contains(keys(var.tags), k)])
    error_message = "tags must contain team, owner, pci-scope, data-class and backup-tier."
  }
}

variable "oidc_issuer" {
  type        = string
  description = "eks output oidc_issuer: Vault verifies the service account tokens of the cluster against it."

  validation {
    condition     = startswith(var.oidc_issuer, "https://")
    error_message = "oidc_issuer must be the https issuer URL of the cluster."
  }
}

variable "vault_bootstrap_role_arn" {
  type        = string
  description = "<prefix>-shared-services-<region-short>-vault-bootstrap: reads the registration to configure the Vault auth mount of the cluster."
}
