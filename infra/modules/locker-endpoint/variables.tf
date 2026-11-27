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
  description = "dev, stage or prod."

  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "environment must be dev, stage or prod."
  }
}

variable "region" {
  type        = string
  description = "Region of the provider."
}

variable "region_short" {
  type        = string
  description = "Short region code, for example euc1."
}

variable "account_id" {
  type        = string
  description = "Account of the VPC; scopes the controller role trust."

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be 12 digits."
  }
}

variable "vpc_id" {
  type        = string
  description = "VPC shared by the cell clusters and the locker cluster of this region."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private app subnets, one per AZ; the load balancer is internal."
}

variable "cluster_domain" {
  type        = string
  description = "deploy.<env>.cluster_domain of config/platform.yaml; the record is <service>.<namespace>.svc.locker.<cluster_domain>, the host the router builds."
}

variable "service" {
  type        = string
  default     = "locker"
  description = "Kubernetes Service of the locker (global.hyperswitch.locker.service)."
}

variable "namespace" {
  type        = string
  default     = "payments"
  description = "Namespace of the locker (global.hyperswitch.locker.namespace)."
}

variable "port" {
  type        = number
  default     = 3001
  description = "Locker port (global.hyperswitch.locker.port); listener and target port."
}

variable "client_security_group_ids" {
  type        = list(string)
  description = "Node security groups of the cell clusters of this region; the only callers the load balancer admits."
}

variable "locker_cluster_name" {
  type        = string
  description = "Locker cluster; its aws-load-balancer-controller registers the locker pods through a TargetGroupBinding."
}

variable "locker_cluster_arn" {
  type        = string
  description = "ARN of the locker cluster; the controller role trusts pods of this cluster only."
}

variable "locker_pod_security_group_id" {
  type        = string
  description = "Pod security group of the locker pods (eks output locker_pod_security_group_id); it admits the load balancer on port."
}

variable "permissions_boundary_arn" {
  type        = string
  description = "workload-boundary of the account."
}

variable "tags" {
  type        = map(string)
  description = "Tags of section 22; team, owner, pci-scope, data-class and backup-tier are required."

  validation {
    condition     = alltrue([for k in ["team", "owner", "pci-scope", "data-class", "backup-tier"] : contains(keys(var.tags), k)])
    error_message = "tags must contain team, owner, pci-scope, data-class and backup-tier."
  }
}
