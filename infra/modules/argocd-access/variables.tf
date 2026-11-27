variable "mode" {
  type        = string
  description = "hub: shared-services, where Argo CD runs (controller role, registration writer role); spoke: an environment account (role the controller assumes)."

  validation {
    condition     = contains(["hub", "spoke"], var.mode)
    error_message = "mode must be hub or spoke."
  }
}

variable "environment" {
  type        = string
  description = "State root of the account: shared-services for the hub, dev, stage or prod for a spoke."

  validation {
    condition     = contains(["dev", "stage", "prod", "shared-services"], var.environment)
    error_message = "environment must be dev, stage, prod or shared-services."
  }
}

variable "name_prefix" {
  type        = string
  description = "Prefix of every resource name; naming.prefix of config/platform.yaml."

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,10}$", var.name_prefix))
    error_message = "name_prefix must be 2 to 11 lower-case letters or digits, starting with a letter."
  }
}

variable "account_id" {
  type        = string
  description = "Account of this stack."

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be 12 digits."
  }
}

variable "shared_services_account_id" {
  type        = string
  description = "Account where Argo CD runs; a spoke trusts its controller role."

  validation {
    condition     = can(regex("^[0-9]{12}$", var.shared_services_account_id))
    error_message = "shared_services_account_id must be 12 digits."
  }
}

variable "spoke_account_ids" {
  type        = map(string)
  default     = {}
  description = "Hub only: environment -> account whose <prefix>-<env>-argocd-controller role the controller may assume and whose eks stacks write registration secrets."
}

variable "cluster_name" {
  type        = string
  default     = null
  description = "Hub only: the central cluster where Argo CD runs; the Pod Identity associations are created in it."
}

variable "cluster_arn" {
  type        = string
  default     = null
  description = "Hub only: ARN of the central cluster; the controller role trusts pods of this cluster only."
}

variable "argocd_namespace" {
  type        = string
  default     = "argocd"
  description = "Namespace of Argo CD in the central cluster."
}

variable "argocd_service_accounts" {
  type        = list(string)
  default     = ["argocd-application-controller", "argocd-server"]
  description = "Service accounts that reach remote clusters: the application controller syncs, the server shows live state."
}

variable "permissions_boundary_arn" {
  type        = string
  description = "workload-boundary of the account, attached to every role."
}

variable "tags" {
  type        = map(string)
  description = "Tags of section 22; team, owner, pci-scope, data-class and backup-tier are required."

  validation {
    condition     = alltrue([for k in ["team", "owner", "pci-scope", "data-class", "backup-tier"] : contains(keys(var.tags), k)])
    error_message = "tags must contain team, owner, pci-scope, data-class and backup-tier."
  }
}
