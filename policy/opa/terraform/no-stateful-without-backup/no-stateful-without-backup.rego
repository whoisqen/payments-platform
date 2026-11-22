package terraform.no_stateful_without_backup

stateful := {
	"aws_rds_cluster",
	"aws_db_instance",
	"aws_dynamodb_table",
	"aws_memorydb_cluster",
	"aws_ebs_volume",
	"aws_efs_file_system",
	"aws_s3_bucket",
	"aws_opensearch_domain",
}

# D2 and D3: the retention of the continuous backup is 35 days, the RDS maximum.
retention_days := 35

# Deletes and no-ops are never judged.
changed(types) := {rc |
	some rc in input.resource_changes
	rc.type in types
	some action in rc.change.actions
	action in {"create", "update"}
}

as_object(x) := x if is_object(x)

as_object(x) := {} if not is_object(x)

# tags_all carries the provider default_tags and wins over tags.
tags(rc) := object.union(as_object(object.get(rc.change.after, "tags", {})), as_object(object.get(rc.change.after, "tags_all", {})))

excepted(rc) if {
	some e in data.exceptions
	e.rule == "terraform.no_stateful_without_backup"
	e.resource == rc.address
	time.parse_rfc3339_ns(concat("", [e.expires, "T23:59:59Z"])) >= time.now_ns()
}

# No plan covers a resource whose tier is absent or none; the written exception list is the only way around.
deny contains msg if {
	some rc in changed(stateful)
	object.get(tags(rc), "backup-tier", "none") == "none"
	not excepted(rc)
	msg := sprintf("%v: stateful resource is not covered by a backup plan (backup-tier absent or none)", [rc.address])
}

deny contains msg if {
	some rc in changed({"aws_rds_cluster"})
	object.get(rc.change.after, "backup_retention_period", 0) < retention_days
	not excepted(rc)
	msg := sprintf("%v: backup_retention_period must be at least %d days for point-in-time recovery", [rc.address, retention_days])
}

deny contains msg if {
	some rc in changed({"aws_dynamodb_table"})
	not pitr_enabled(rc)
	not excepted(rc)
	msg := sprintf("%v: point_in_time_recovery must be enabled", [rc.address])
}

pitr_enabled(rc) if rc.change.after.point_in_time_recovery[0].enabled == true
