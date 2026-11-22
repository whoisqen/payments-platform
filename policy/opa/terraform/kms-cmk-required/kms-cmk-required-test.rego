package terraform.kms_cmk_required_test

import data.terraform.kms_cmk_required

cde_tags := {"pci-scope": "cde", "data-class": "card-data"}

other_tags := {"pci-scope": "out-of-scope", "data-class": "internal"}

key := "arn:aws:kms:eu-central-1:123456789012:key/11111111-2222-3333-4444-555555555555"

rc(type, address, after) := {"type": type, "address": address, "change": {"actions": ["create"], "after": after, "after_unknown": {}}}

plan(changes) := {"resource_changes": changes}

test_cde_aurora_with_cmk_allowed if {
	r := rc("aws_rds_cluster", "aws_rds_cluster.cell0", {"tags_all": cde_tags, "storage_encrypted": true, "kms_key_id": key})
	count(kms_cmk_required.deny) == 0 with input as plan([r])
}

test_cde_aurora_without_key_denied if {
	r := rc("aws_rds_cluster", "aws_rds_cluster.cell0", {"tags_all": cde_tags, "storage_encrypted": true})
	count(kms_cmk_required.deny) == 1 with input as plan([r])
}

test_cde_aurora_unencrypted_denied if {
	r := rc("aws_rds_cluster", "aws_rds_cluster.cell0", {"tags_all": cde_tags, "storage_encrypted": false, "kms_key_id": key})
	count(kms_cmk_required.deny) == 1 with input as plan([r])
}

test_cde_aurora_with_key_known_after_apply_allowed if {
	r := {"type": "aws_rds_cluster", "address": "aws_rds_cluster.cell0", "change": {"actions": ["create"], "after": {"tags_all": cde_tags, "storage_encrypted": true}, "after_unknown": {"kms_key_id": true}}}
	count(kms_cmk_required.deny) == 0 with input as plan([r])
}

test_cde_ebs_with_aws_managed_alias_denied if {
	r := rc("aws_ebs_volume", "aws_ebs_volume.data", {"tags_all": cde_tags, "encrypted": true, "kms_key_id": "alias/aws/ebs"})
	count(kms_cmk_required.deny) == 1 with input as plan([r])
}

test_non_cde_aurora_without_key_allowed if {
	r := rc("aws_rds_cluster", "aws_rds_cluster.analytics", {"tags_all": other_tags, "storage_encrypted": true})
	count(kms_cmk_required.deny) == 0 with input as plan([r])
}

test_cde_memorydb_without_key_denied if {
	r := rc("aws_memorydb_cluster", "aws_memorydb_cluster.cell0", {"tags_all": cde_tags})
	count(kms_cmk_required.deny) == 1 with input as plan([r])
}

test_cde_dynamodb_with_cmk_allowed if {
	r := rc("aws_dynamodb_table", "aws_dynamodb_table.cell_map", {"tags_all": cde_tags, "server_side_encryption": [{"enabled": true, "kms_key_arn": key}]})
	count(kms_cmk_required.deny) == 0 with input as plan([r])
}

test_cde_dynamodb_default_encryption_denied if {
	r := rc("aws_dynamodb_table", "aws_dynamodb_table.cell_map", {"tags_all": cde_tags, "server_side_encryption": []})
	count(kms_cmk_required.deny) == 1 with input as plan([r])
}

test_cde_msk_with_cmk_allowed if {
	r := rc("aws_msk_cluster", "aws_msk_cluster.events", {"tags_all": cde_tags, "encryption_info": [{"encryption_at_rest_kms_key_arn": key}]})
	count(kms_cmk_required.deny) == 0 with input as plan([r])
}

test_cde_msk_without_cmk_denied if {
	r := rc("aws_msk_cluster", "aws_msk_cluster.events", {"tags_all": cde_tags, "encryption_info": [{}]})
	count(kms_cmk_required.deny) == 1 with input as plan([r])
}

test_deleted_resource_ignored if {
	r := {"type": "aws_rds_cluster", "address": "aws_rds_cluster.cell0", "change": {"actions": ["delete"], "after": null}}
	count(kms_cmk_required.deny) == 0 with input as plan([r])
}

test_active_exception_allows if {
	r := rc("aws_memorydb_cluster", "aws_memorydb_cluster.cell0", {"tags_all": cde_tags})
	ex := [{"rule": "terraform.kms_cmk_required", "resource": "aws_memorydb_cluster.cell0", "owner": "platform", "reason": "test", "expires": "2200-12-31"}]
	count(kms_cmk_required.deny) == 0 with input as plan([r]) with data.exceptions as ex
}
