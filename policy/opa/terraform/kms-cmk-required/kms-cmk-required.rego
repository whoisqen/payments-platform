package terraform.kms_cmk_required

flag_attr := {
	"aws_db_instance": "storage_encrypted",
	"aws_rds_cluster": "storage_encrypted",
	"aws_ebs_volume": "encrypted",
	"aws_efs_file_system": "encrypted",
}

key_attr := {
	"aws_db_instance": "kms_key_id",
	"aws_rds_cluster": "kms_key_id",
	"aws_ebs_volume": "kms_key_id",
	"aws_efs_file_system": "kms_key_id",
	"aws_memorydb_cluster": "kms_key_arn",
}

# Deletes and no-ops are never judged.
changed(types) := {rc |
	some rc in input.resource_changes
	rc.type in types
	some action in rc.change.actions
	action in {"create", "update"}
}

after(rc) := rc.change.after

unknown_of(rc) := object.get(rc.change, "after_unknown", {})

# The plan JSON has no account, so the CDE is recognised by the pci-scope and data-class tags (tags_all holds default_tags).
cde(rc) if after(rc).tags_all["pci-scope"] == "cde"

cde(rc) if after(rc).tags["pci-scope"] == "cde"

cde(rc) if after(rc).tags_all["data-class"] == "card-data"

excepted(rc) if {
	some e in data.exceptions
	e.rule == "terraform.kms_cmk_required"
	e.resource == rc.address
	time.parse_rfc3339_ns(concat("", [e.expires, "T23:59:59Z"])) >= time.now_ns()
}

# A key known only after apply is a reference to a key created in the same plan.
key_ok(value, unknown) if unknown == true

key_ok(value, _) if {
	is_string(value)
	value != ""
	not startswith(value, "alias/aws/")
}

deny contains msg if {
	some rc in changed(object.keys(key_attr))
	cde(rc)
	not key_ok(object.get(after(rc), key_attr[rc.type], null), object.get(unknown_of(rc), key_attr[rc.type], false))
	not excepted(rc)
	msg := sprintf("%v: %v must be a customer managed KMS key", [rc.address, key_attr[rc.type]])
}

deny contains msg if {
	some rc in changed(object.keys(flag_attr))
	cde(rc)
	after(rc)[flag_attr[rc.type]] != true
	not excepted(rc)
	msg := sprintf("%v: %v must be true", [rc.address, flag_attr[rc.type]])
}

deny contains msg if {
	some rc in changed({"aws_dynamodb_table"})
	cde(rc)
	not dynamodb_cmk(rc)
	not excepted(rc)
	msg := sprintf("%v: server_side_encryption must be enabled with a customer managed kms_key_arn", [rc.address])
}

dynamodb_cmk(rc) if {
	sse := after(rc).server_side_encryption[0]
	sse.enabled == true
	key_ok(object.get(sse, "kms_key_arn", null), object.get(unknown_of(rc), ["server_side_encryption", 0, "kms_key_arn"], false))
}

deny contains msg if {
	some rc in changed({"aws_msk_cluster"})
	cde(rc)
	not msk_cmk(rc)
	not excepted(rc)
	msg := sprintf("%v: encryption_at_rest_kms_key_arn must be a customer managed KMS key", [rc.address])
}

msk_cmk(rc) if {
	enc := after(rc).encryption_info[0]
	key_ok(object.get(enc, "encryption_at_rest_kms_key_arn", null), false)
}

msk_cmk(rc) if {
	object.get(unknown_of(rc), ["encryption_info", 0, "encryption_at_rest_kms_key_arn"], false) == true
}
