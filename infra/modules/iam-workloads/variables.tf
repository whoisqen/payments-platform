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
  description = "dev, stage or prod."
  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "environment must be dev, stage or prod."
  }
}

variable "cell" {
  type        = string
  description = "Cluster the roles serve: a cell (cell-0 to cell-3, spare) or a shared cluster (locker, edge, control-center); part of every role name."
  validation {
    condition     = can(regex("^(cell-[0-3]|spare|locker|edge|control-center)$", var.cell))
    error_message = "cell must be cell-0 to cell-3, spare, locker, edge or control-center."
  }
}

variable "account_id" {
  type        = string
  description = "AWS account of the cluster; builds the MemoryDB user ARNs and the source account condition."
  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be 12 digits."
  }
}

variable "cluster_name" {
  type        = string
  description = "Cluster of the cell (eks module); the pod identity associations are created in it."
}

variable "cluster_arn" {
  type        = string
  description = "Cluster ARN; the trust policy accepts only pods of this cluster."
}

variable "permissions_boundary_arn" {
  type        = string
  description = "Boundary policy (workload-boundary) attached to every role."
}

variable "deny_recovery_writes_policy_arn" {
  type        = string
  description = "deny_recovery_writes_policy_arn of dynamodb-global; every service role attaches it so that no write reaches a recovery replica."
}

variable "memorydb" {
  type = object({
    cluster_arn = string
    users       = map(string)
  })
  default     = null
  description = "MemoryDB cluster of the cell and the ACL user of each service (key = service name); a service without a user gets no MemoryDB access."
}

variable "rds_db_connect_arns" {
  type        = map(list(string))
  default     = {}
  description = "rds-db:connect resource ARNs per service (arn:aws:rds-db:<region>:<account>:dbuser:<resource-id>/<user>); a service without entries gets no database access."
}

variable "locker_kms_key_arn" {
  type        = string
  default     = null
  description = "Key of the locker; only the locker role may use it. Required when services lists locker."
}

variable "cell_kms_key_arn" {
  type        = string
  default     = null
  description = "Key of the cell (kms key_arns[<cell>]): router encrypts and decrypts with it, drainer and scheduler decrypt only. null grants nothing."
}

variable "services" {
  type        = list(string)
  default     = ["router", "locker", "drainer", "scheduler"]
  description = "Workloads of this cluster that get a role (service account = name, namespace = workload_namespace); external-secrets always does."
  validation {
    condition     = alltrue([for s in var.services : contains(["router", "locker", "drainer", "scheduler"], s)])
    error_message = "services may list router, locker, drainer and scheduler."
  }
}

variable "workload_namespace" {
  type        = string
  default     = "payments"
  description = "Namespace the ApplicationSets deploy the workloads to (payments for cells and the locker)."
}

variable "migrator" {
  type = object({
    db_connect_arns  = list(string)
    backup_vault_arn = string
    backup_role_arn  = string
  })
  default     = null
  description = "Role of the migration Job (service account migrator): IAM login as hs_migrator on the writer (db_connect_arns), and the pre-migration AWS Backup job (start in backup_vault_arn, pass backup_role_arn). null creates no role."
}

variable "secrets_kms_key_arn" {
  type        = string
  description = "Key of the Secrets Manager secrets that external-secrets reads."
}

variable "secret_arns" {
  type        = list(string)
  default     = []
  description = "Secrets external-secrets may read, by ARN; empty means no access."
}

variable "dynamodb_table_arn" {
  type        = string
  default     = null
  description = "Merchant-to-cell table; router and scheduler read it, nobody writes from a cell."
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

variable "kafka_producer_policy_arn" {
  type        = string
  default     = null
  description = "producer_policy_arn of the msk module; null attaches nothing."
}

variable "kafka_producers" {
  type        = list(string)
  default     = ["router", "scheduler"]
  description = "Services that publish events to MSK (the Hyperswitch Kafka store runs in router and scheduler)."

  validation {
    condition     = alltrue([for s in var.kafka_producers : contains(["router", "drainer", "scheduler"], s)])
    error_message = "kafka_producers may list router, drainer and scheduler; the locker never publishes events."
  }
}

variable "yace" {
  type = object({
    enabled         = optional(bool, true)
    namespace       = optional(string, "monitoring")
    service_account = optional(string, "yace")
  })
  default     = {}
  description = "CloudWatch exporter role of the cluster: read-only metrics and tag discovery through Pod Identity."
}
