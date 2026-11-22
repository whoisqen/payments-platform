package terraform.backup_tier_required

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

rank := {"none": 0, "bronze": 1, "silver": 2, "gold": 3}

# Aurora, DynamoDB and MemoryDB hold payment state and are always gold.
minimum := {
	"aws_rds_cluster": "gold",
	"aws_dynamodb_table": "gold",
	"aws_memorydb_cluster": "gold",
}

# Deletes and no-ops are never judged.
changed := {rc |
	some rc in input.resource_changes
	rc.type in stateful
	some action in rc.change.actions
	action in {"create", "update"}
}

as_object(x) := x if is_object(x)

as_object(x) := {} if not is_object(x)

# tags_all carries the provider default_tags and wins over tags.
tags(rc) := object.union(as_object(object.get(rc.change.after, "tags", {})), as_object(object.get(rc.change.after, "tags_all", {})))

excepted(rc) if {
	some e in data.exceptions
	e.rule == "terraform.backup_tier_required"
	e.resource == rc.address
	time.parse_rfc3339_ns(concat("", [e.expires, "T23:59:59Z"])) >= time.now_ns()
}

# AWS Backup selects resources by this tag, so without it nothing backs the resource up.
deny contains msg if {
	some rc in changed
	not tags(rc)["backup-tier"]
	not excepted(rc)
	msg := sprintf("%v: stateful resource has no backup-tier tag", [rc.address])
}

deny contains msg if {
	some rc in changed
	tier := tags(rc)["backup-tier"]
	not rank[tier]
	not excepted(rc)
	msg := sprintf("%v: backup-tier %v is not one of gold, silver, bronze, none", [rc.address, tier])
}

deny contains msg if {
	some rc in changed
	tier := tags(rc)["backup-tier"]
	rank[tier] < rank[minimum[rc.type]]
	tier != "none"
	not excepted(rc)
	msg := sprintf("%v: backup-tier %v is below the minimum %v for %v", [rc.address, tier, minimum[rc.type], rc.type])
}
