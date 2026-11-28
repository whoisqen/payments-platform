mock_provider "opensearch" {}

variables {
  groups = {
    admin       = "pay-grafana-admins"
    sre         = "pay-sre"
    security    = "pay-security"
    engineering = "pay-engineering"
  }
  master_user_arn        = "arn:aws:iam::222222222222:role/pay-shared-services-tf-exec"
  app_writer_role_arns   = ["arn:aws:iam::222222222222:role/logstash"]
  audit_writer_role_arns = ["arn:aws:iam::222222222222:role/audit-ingest"]
  monitor_role_arns      = ["arn:aws:iam::222222222222:role/es-exporter"]
  grafana_role_arns      = ["arn:aws:iam::222222222222:role/grafana"]
  env_reader_role_arns = {
    dev  = "arn:aws:iam::111111111111:role/admin-agent-dev"
    prod = "arn:aws:iam::444444444444:role/admin-agent-prod"
  }
}

run "one_app_stream_per_environment_and_the_audit_stream" {
  command = plan

  assert {
    condition     = toset(keys(opensearch_data_stream.this)) == toset(["logs-app-dev", "logs-app-stage", "logs-app-prod", "logs-app-shared-services", "logs-audit"])
    error_message = "data streams logs-app-<env> and logs-audit"
  }

  assert {
    condition = (
      jsondecode(opensearch_composable_index_template.this["logs-audit"].body).template.settings["index.number_of_shards"] == 3 &&
      jsondecode(opensearch_composable_index_template.this["logs-app-prod"].body).template.settings["index.number_of_replicas"] == 1
    )
    error_message = "3 primaries and 1 replica"
  }
}

run "lifecycle_matches_the_retention" {
  command = plan

  assert {
    condition = (
      jsondecode(opensearch_ism_policy.this["app"].body).policy.states[0].actions[0].rollover.min_primary_shard_size == "30gb" &&
      jsondecode(opensearch_ism_policy.this["app"].body).policy.states[0].transitions[0].conditions.min_rollover_age == "7d" &&
      jsondecode(opensearch_ism_policy.this["app"].body).policy.states[1].transitions[0].conditions.min_rollover_age == "30d" &&
      jsondecode(opensearch_ism_policy.this["audit"].body).policy.states[0].actions[0].rollover.min_primary_shard_size == "10gb" &&
      jsondecode(opensearch_ism_policy.this["audit"].body).policy.states[0].transitions[0].conditions.min_rollover_age == "30d" &&
      jsondecode(opensearch_ism_policy.this["audit"].body).policy.states[1].transitions[0].conditions.min_rollover_age == "365d"
    )
    error_message = "app hot 7 days and deleted at 30; audit hot 30 days and deleted at 365"
  }
}

run "engineering_reads_application_logs_only" {
  command = plan

  assert {
    condition = alltrue([
      for p in opensearch_role.read["engineering"].index_permissions : alltrue([for i in p.index_patterns : !strcontains(i, "audit")])
    ])
    error_message = "engineering never sees the audit trail"
  }

  assert {
    condition     = opensearch_roles_mapping.write["app"].backend_roles == toset(["arn:aws:iam::222222222222:role/logstash"])
    error_message = "Logstash is the application log writer"
  }

  assert {
    condition     = contains(opensearch_roles_mapping.all_access.backend_roles, var.master_user_arn)
    error_message = "the master role stays in all_access"
  }
}

run "shards_outside_10_to_50_gb_are_rejected" {
  command = plan

  variables {
    streams = {
      app   = { primary_shards = 3, replicas = 1, rollover_shard_size = "60gb", rollover_age = "1d", hot_days = 7, delete_after_days = 30 }
      audit = { primary_shards = 3, replicas = 1, rollover_shard_size = "10gb", rollover_age = "1d", hot_days = 30, delete_after_days = 365 }
    }
  }

  expect_failures = [var.streams]
}

run "admin_agent_reads_its_own_environment_only" {
  command = plan

  assert {
    condition = (
      one(opensearch_role.env_reader["dev"].index_permissions).index_patterns == toset(["logs-app-dev", ".ds-logs-app-dev-*"]) &&
      opensearch_roles_mapping.env_reader["prod"].backend_roles == toset(["arn:aws:iam::444444444444:role/admin-agent-prod"])
    )
    error_message = "each admin agent role reads only logs-app-<env>"
  }

  assert {
    condition     = jsondecode(opensearch_composable_index_template.this["logs-app-dev"].body).template.mappings.properties["resource.k8s.namespace.name"].type == "keyword"
    error_message = "the filter fields are keywords"
  }

  assert {
    condition     = jsondecode(opensearch_composable_index_template.this["logs-app-prod"].body).template.mappings.properties.attributes.type == "flat_object"
    error_message = "attributes cannot clash between services"
  }

  assert {
    condition     = alltrue([for p in opensearch_role.grafana.index_permissions : alltrue([for i in p.index_patterns : !strcontains(i, "audit")])]) && opensearch_roles_mapping.grafana.backend_roles == toset(["arn:aws:iam::222222222222:role/grafana"])
    error_message = "Grafana reads application logs only"
  }
}

run "exporter_reads_statistics_only" {
  command = plan

  assert {
    condition = (
      opensearch_role.monitor.cluster_permissions == toset(["cluster:monitor/*"]) &&
      one(opensearch_role.monitor.index_permissions).allowed_actions == toset(["indices:monitor/*"]) &&
      opensearch_roles_mapping.monitor.backend_roles == toset(["arn:aws:iam::222222222222:role/es-exporter"])
    )
    error_message = "the exporter gets monitor actions only"
  }
}
