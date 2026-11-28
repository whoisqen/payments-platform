locals {
  app_streams = { for e in var.environments : e => "logs-app-${e}" }
  streams     = merge({ for e, n in local.app_streams : n => "app" }, { "logs-audit" = "audit" })
  patterns    = { app = ["logs-app-*"], audit = ["logs-audit"] }
  # Permissions apply to the data stream and to its backing indices, which carry the .ds- prefix.
  index_patterns = { for k, p in local.patterns : k => concat(p, [for x in p : ".ds-${x}*"]) }
  read_actions   = ["read", "indices:admin/mappings/get", "indices:admin/resolve/index", "indices:monitor/settings/get"]
  write_actions  = ["crud", "create_index", "indices:admin/mapping/put", "indices:admin/data_stream/get", "indices:admin/data_stream/create"]
}

# Hot until hot_days after rollover, then UltraWarm, then deleted; the ISM template attaches each new backing index.
resource "opensearch_ism_policy" "this" {
  for_each = var.streams

  policy_id = "logs-${each.key}"
  body = jsonencode({
    policy = {
      description   = "logs-${each.key}: hot ${each.value.hot_days} days, UltraWarm until day ${each.value.delete_after_days}, then deleted"
      default_state = "hot"
      states = [
        {
          name = "hot"
          actions = [{
            retry    = { count = 3, backoff = "exponential", delay = "10m" }
            rollover = { min_primary_shard_size = each.value.rollover_shard_size, min_index_age = each.value.rollover_age }
          }]
          transitions = [{ state_name = "warm", conditions = { min_rollover_age = "${each.value.hot_days}d" } }]
        },
        {
          name = "warm"
          actions = [{
            retry          = { count = 5, backoff = "exponential", delay = "1h" }
            warm_migration = {}
          }]
          transitions = [{ state_name = "delete", conditions = { min_rollover_age = "${each.value.delete_after_days}d" } }]
        },
        {
          name        = "delete"
          actions     = [{ delete = {} }]
          transitions = []
        },
      ]
      ism_template = [{ index_patterns = local.patterns[each.key], priority = 100 }]
    }
  })
}

resource "opensearch_composable_index_template" "this" {
  for_each = local.streams

  name = each.key
  body = jsonencode({
    index_patterns = [each.key]
    data_stream    = {}
    priority       = 200
    template = {
      settings = {
        "index.number_of_shards"   = var.streams[each.value].primary_shards
        "index.number_of_replicas" = var.streams[each.value].replicas
        "index.codec"              = "best_compression"
        "index.refresh_interval"   = "10s"
      }
      # Fields the admin agent and the dashboards filter on.
      mappings = {
        properties = {
          "@timestamp"                  = { type = "date" }
          "resource.k8s.namespace.name" = { type = "keyword" }
          "resource.service.name"       = { type = "keyword" }
          "severity.text"               = { type = "keyword" }
          body                          = { type = "text" }
          # Free-form record attributes: one field, so a type clash between services cannot reject records.
          attributes = { type = "flat_object" }
        }
      }
    }
  })
}

# Created up front so the writers need no right to create them and the ISM policy is in place before the first document.
resource "opensearch_data_stream" "this" {
  for_each = local.streams

  name = each.key

  depends_on = [opensearch_composable_index_template.this, opensearch_ism_policy.this]
}

resource "opensearch_role" "read" {
  for_each = {
    sre         = { description = "On-call and platform engineers: application logs and the audit trail", streams = ["app", "audit"] }
    security    = { description = "Security engineers: the audit trail and application logs for investigations", streams = ["app", "audit"] }
    engineering = { description = "Developers: application logs only", streams = ["app"] }
  }

  role_name           = "logs_${each.key}"
  description         = each.value.description
  cluster_permissions = ["cluster_composite_ops_ro"]

  index_permissions {
    index_patterns  = flatten([for s in each.value.streams : local.index_patterns[s]])
    allowed_actions = local.read_actions
  }

  tenant_permissions {
    tenant_patterns = ["global_tenant"]
    allowed_actions = each.key == "engineering" ? ["kibana_all_read"] : ["kibana_all_write"]
  }
}

# Grafana data source (Pod Identity role of monitoring/grafana): application logs of every environment.
resource "opensearch_role" "grafana" {
  role_name           = "logs_grafana"
  description         = "Grafana: application logs of every environment"
  cluster_permissions = ["cluster_composite_ops_ro"]

  index_permissions {
    index_patterns  = local.index_patterns.app
    allowed_actions = local.read_actions
  }
}

resource "opensearch_roles_mapping" "grafana" {
  role_name     = opensearch_role.grafana.role_name
  backend_roles = var.grafana_role_arns
  description   = "IAM role of Grafana"
}

resource "opensearch_role" "write" {
  for_each = { app = "Logstash: application logs of every environment", audit = "Ingestion pipeline: CloudTrail and EKS audit from the log archive" }

  role_name           = "logs_${each.key}_writer"
  description         = each.value
  cluster_permissions = ["cluster_monitor", "cluster_composite_ops", "indices:admin/template/get", "indices:admin/index_template/get"]

  index_permissions {
    index_patterns  = local.index_patterns[each.key]
    allowed_actions = local.write_actions
  }
}

resource "opensearch_roles_mapping" "read" {
  for_each = opensearch_role.read

  role_name     = each.value.role_name
  backend_roles = [var.groups[each.key]]
  description   = "Dashboards group ${var.groups[each.key]}"
}

resource "opensearch_roles_mapping" "write" {
  for_each = opensearch_role.write

  role_name     = each.value.role_name
  backend_roles = each.key == "app" ? var.app_writer_role_arns : var.audit_writer_role_arns
  description   = "IAM roles that write logs-${each.key}"
}

# The module owns these built-in mappings, so the master role stays in all_access next to the admin group.
resource "opensearch_roles_mapping" "all_access" {
  role_name     = "all_access"
  backend_roles = [var.master_user_arn, var.groups.admin]
  description   = "Domain administrators"
}

resource "opensearch_roles_mapping" "security_manager" {
  role_name     = "security_manager"
  backend_roles = [var.master_user_arn, var.groups.admin]
  description   = "Domain administrators"
}

resource "opensearch_roles_mapping" "dashboards_user" {
  role_name     = "kibana_user"
  backend_roles = [var.groups.admin, var.groups.sre, var.groups.security, var.groups.engineering]
  description   = "Every Dashboards group may open Dashboards"
}

# The admin agent of each environment signs with its environment role and reads only the application logs of that environment.
resource "opensearch_role" "env_reader" {
  for_each = var.env_reader_role_arns

  role_name           = "logs_reader_${each.key}"
  description         = "Admin agent of ${each.key}: logs-app-${each.key} only"
  cluster_permissions = []

  index_permissions {
    index_patterns  = ["logs-app-${each.key}", ".ds-logs-app-${each.key}-*"]
    allowed_actions = local.read_actions
  }
}

resource "opensearch_roles_mapping" "env_reader" {
  for_each = var.env_reader_role_arns

  role_name     = opensearch_role.env_reader[each.key].role_name
  backend_roles = [each.value]
  description   = "Admin agent role of ${each.key}"
}

# elasticsearch_exporter: cluster, node and index statistics, no document reads.
resource "opensearch_role" "monitor" {
  role_name           = "logs_monitor"
  description         = "elasticsearch_exporter: statistics only"
  cluster_permissions = ["cluster:monitor/*"]

  index_permissions {
    index_patterns  = ["*"]
    allowed_actions = ["indices:monitor/*"]
  }
}

resource "opensearch_roles_mapping" "monitor" {
  role_name     = opensearch_role.monitor.role_name
  backend_roles = var.monitor_role_arns
  description   = "IAM roles of the metrics exporter"
}
