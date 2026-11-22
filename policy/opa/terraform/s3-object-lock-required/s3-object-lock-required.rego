package terraform.s3_object_lock_required

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
	e.rule == "terraform.s3_object_lock_required"
	e.resource == rc.address
	time.parse_rfc3339_ns(concat("", [e.expires, "T23:59:59Z"])) >= time.now_ns()
}

# Gold buckets (audit logs, backups, Terraform state and their replicas) are immutable for PCI DSS 10.5.1 and ransomware protection.
deny contains msg if {
	some rc in changed({"aws_s3_bucket"})
	tags(rc)["backup-tier"] == "gold"
	not lock_enabled(rc)
	not excepted(rc)
	msg := sprintf("%v: a gold-tier bucket needs object_lock_enabled = true", [rc.address])
}

lock_enabled(rc) if rc.change.after.object_lock_enabled == true

deny contains msg if {
	some rc in changed({"aws_s3_bucket_object_lock_configuration"})
	not default_retention_set(rc)
	not excepted(rc)
	msg := sprintf("%v: the object lock configuration needs a COMPLIANCE or GOVERNANCE default retention", [rc.address])
}

default_retention_set(rc) if {
	r := rc.change.after.rule[0].default_retention[0]
	r.mode in {"COMPLIANCE", "GOVERNANCE"}
	max([object.get(r, "days", 0), object.get(r, "years", 0)]) > 0
}
