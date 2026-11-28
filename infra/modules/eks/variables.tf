variable "region" {
  type        = string
  description = "Region of the provider this module instance runs in."
  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.region))
    error_message = "region must be an AWS region name such as eu-west-1."
  }
}

variable "environment" {
  type        = string
  description = "dev, stage, prod or shared-services (the CI account)."
  validation {
    condition     = contains(["dev", "stage", "prod", "shared-services"], var.environment)
    error_message = "environment must be dev, stage, prod or shared-services."
  }
}

variable "component" {
  type        = string
  description = "Cluster name segment, for example eks-cell-0 or eks-edge; the cluster is pay-<env>-<region-short>-<component>."
}

variable "kubernetes_version" {
  type        = string
  description = "Control plane version; node images and add-ons follow it."
  validation {
    condition     = can(regex("^1\\.[0-9]{2}$", var.kubernetes_version))
    error_message = "kubernetes_version must look like 1.37."
  }
}

variable "vpc_id" {
  type        = string
  description = "VPC of the cluster."
}

variable "vpc_cidr_block" {
  type        = string
  description = "VPC CIDR; node egress inside the VPC is limited to it."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private app subnets, one per AZ; the endpoint is private and no public subnet is used."
  validation {
    condition     = length(var.subnet_ids) == 3
    error_message = "subnet_ids must list one subnet in each of three AZs."
  }
}

variable "secrets_kms_key_arn" {
  type        = string
  description = "Customer managed key for Kubernetes Secrets envelope encryption."
}

variable "logs_kms_key_arn" {
  type        = string
  description = "Customer managed key of the control-plane log group; its policy must allow logs.amazonaws.com."
}

variable "ebs_kms_key_arn" {
  type        = string
  description = "Key of the node and volume encryption (pay-<env>-<region-short>-ebs-nodes)."
}

variable "permissions_boundary_arn" {
  type        = string
  description = "Boundary policy of policy/iam/boundaries attached to every role of the cluster."
}

variable "log_retention_days" {
  type        = number
  default     = 365
  description = "CloudWatch retention of control-plane logs; PCI DSS 10.5.1 keeps one year, so below 365 needs log_archive."
}

variable "log_archive" {
  type = object({
    bucket_arn = string
    account_id = string
    prefix     = optional(string, "eks")
  })
  default     = null
  description = "Log archive bucket (Object Lock, one year) that receives the control-plane logs through Firehose; null keeps them in CloudWatch only."
  validation {
    condition     = var.log_archive == null || (can(regex("^arn:aws:s3:::[a-z0-9.-]+$", var.log_archive.bucket_arn)) && can(regex("^[0-9]{12}$", var.log_archive.account_id)))
    error_message = "log_archive needs a bucket ARN and the 12-digit account id of the archive."
  }
}

variable "access_entries" {
  type = map(object({
    principal_arn     = string
    policy_arn        = string
    scope             = optional(string, "cluster")
    namespaces        = optional(list(string), [])
    kubernetes_groups = optional(list(string), [])
  }))
  default     = {}
  description = "EKS access entries by name; people get view only, ArgoCD a namespaced scope, nobody cluster-admin."
  validation {
    condition     = alltrue([for e in var.access_entries : !endswith(e.policy_arn, "/AmazonEKSClusterAdminPolicy") && contains(["cluster", "namespace"], e.scope)])
    error_message = "cluster-admin is not allowed and scope must be cluster or namespace."
  }
}

variable "addon_versions" {
  type        = map(string)
  default     = {}
  description = "Pinned add-on versions by add-on name; an add-on without an entry takes the default version of kubernetes_version."
}

variable "bootstrap_instance_types" {
  type        = list(string)
  default     = ["m7g.large"]
  description = "Types of the small managed node group that hosts CoreDNS and Karpenter, which cannot start on nodes they provision."
}

variable "bootstrap_node_count" {
  type        = number
  default     = 3
  description = "Bootstrap nodes, at least one per AZ."
  validation {
    condition     = var.bootstrap_node_count >= 3
    error_message = "bootstrap_node_count must keep one node in each AZ."
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

variable "name_prefix" {
  type        = string
  description = "Prefix of every resource name, for example the project short name; set from config/platform.yaml (naming.prefix)."

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,10}$", var.name_prefix))
    error_message = "name_prefix must be 2 to 11 lower-case letters or digits, starting with a letter."
  }
}

variable "locker_pod_endpoint_cidrs" {
  description = "CIDRs of the subnets that hold the VPC interface endpoints (KMS on 443); empty uses vpc_cidr_block. Ignored when locker_pod_endpoint_security_group_id is set."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.locker_pod_endpoint_cidrs : can(cidrhost(c, 0))])
    error_message = "locker_pod_endpoint_cidrs must hold valid IPv4 CIDRs."
  }
}

variable "locker_pod_database_cidrs" {
  description = "CIDRs of the data subnets that hold the card-vault RDS Proxy (5432); empty uses vpc_cidr_block."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.locker_pod_database_cidrs : can(cidrhost(c, 0))])
    error_message = "locker_pod_database_cidrs must hold valid IPv4 CIDRs."
  }
}

variable "locker_pod_endpoint_security_group_id" {
  description = "Security group of the VPC interface endpoints (vpc output endpoint_security_group_id); when set, the 443 rule targets it instead of CIDRs."
  type        = string
  default     = null
}

variable "argocd_cluster_name" {
  type        = string
  default     = null
  description = "Cluster name Argo CD and the ApplicationSets use (<prefix>-<env>-<region-short>-<cell, locker, edge or control-center>); null drops the eks- prefix of component."
}

variable "container_log_max_size" {
  type        = string
  default     = "50Mi"
  description = "Size at which kubelet rotates a container log (Bottlerocket settings.kubernetes.container-log-max-size)."

  validation {
    condition     = can(regex("^[0-9]+(Ki|Mi|Gi)$", var.container_log_max_size))
    error_message = "container_log_max_size must look like 50Mi."
  }
}

variable "container_log_max_files" {
  type        = number
  default     = 5
  description = "Rotated container log files kubelet keeps per container (settings.kubernetes.container-log-max-files)."

  validation {
    condition     = var.container_log_max_files >= 2
    error_message = "container_log_max_files must be at least 2."
  }
}

variable "api_ingress_cidrs" {
  type        = list(string)
  default     = []
  description = "CIDRs outside the VPC admitted to the private API endpoint on 443: the node and pod subnets of the central cluster (Argo CD, Vault)."

  validation {
    condition     = alltrue([for c in var.api_ingress_cidrs : can(cidrhost(c, 0)) && c != "0.0.0.0/0"])
    error_message = "api_ingress_cidrs must hold valid IPv4 CIDRs other than 0.0.0.0/0."
  }
}

variable "central_egress" {
  type = object({
    cidrs = list(string)
    ports = list(number)
  })
  default     = { cidrs = [], ports = [] }
  description = "Node egress to shared-services beyond HTTPS: the hub CIDRs and the ports of Tempo OTLP (4317) and Logstash (8443)."

  validation {
    condition     = alltrue([for c in var.central_egress.cidrs : can(cidrhost(c, 0)) && c != "0.0.0.0/0"]) && alltrue([for p in var.central_egress.ports : p >= 1 && p <= 65535])
    error_message = "central_egress needs valid IPv4 CIDRs other than 0.0.0.0/0 and ports between 1 and 65535."
  }
}
