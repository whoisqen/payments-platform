package terraform.required_tags

# Deletes and no-ops are never judged.
changed := {rc |
	some rc in input.resource_changes
	some action in rc.change.actions
	action in {"create", "update"}
}

as_object(x) := x if is_object(x)

as_object(x) := {} if not is_object(x)

# tags_all carries the provider default_tags and wins over tags.
tags(rc) := object.union(as_object(object.get(rc.change.after, "tags", {})), as_object(object.get(rc.change.after, "tags_all", {})))

taggable(rc) if "tags" in object.keys(rc.change.after)

taggable(rc) if "tags_all" in object.keys(rc.change.after)

# Tags that are unknown until apply cannot be judged in the plan.
tags_unknown(rc) if object.get(object.get(rc.change, "after_unknown", {}), "tags_all", false) == true

excepted(rc) if {
	some e in data.exceptions
	e.rule == "terraform.required_tags"
	e.resource == rc.address
	time.parse_rfc3339_ns(concat("", [e.expires, "T23:59:59Z"])) >= time.now_ns()
}

judged contains rc if {
	some rc in changed
	taggable(rc)
	not tags_unknown(rc)
	not excepted(rc)
}

deny contains msg if {
	some rc in judged
	some key, spec in data.tag_schema
	spec.required
	not tags(rc)[key]
	msg := sprintf("%v: required tag %v is missing", [rc.address, key])
}

deny contains msg if {
	some rc in judged
	some key, spec in data.tag_schema
	value := tags(rc)[key]
	allowed := spec.values
	not value in allowed
	msg := sprintf("%v: tag %v has value %v outside %v", [rc.address, key, value, spec.values])
}

deny contains msg if {
	some rc in judged
	some key, spec in data.tag_schema
	value := tags(rc)[key]
	pattern := spec.pattern
	not regex.match(pattern, value)
	msg := sprintf("%v: tag %v value %v does not match %v", [rc.address, key, value, pattern])
}

deny contains msg if {
	some rc in judged
	some key, _ in data.tag_schema
	tags(rc)[key] == ""
	msg := sprintf("%v: tag %v is empty", [rc.address, key])
}
