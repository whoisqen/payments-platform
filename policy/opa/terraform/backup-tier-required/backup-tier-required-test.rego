package terraform.backup_tier_required_test

import data.terraform.backup_tier_required

rc(type, address, after) := {"type": type, "address": address, "change": {"actions": ["create"], "after": after}}

plan(changes) := {"resource_changes": changes}

test_gold_aurora_allowed if {
	r := rc("aws_rds_cluster", "aws_rds_cluster.cell0", {"tags_all": {"backup-tier": "gold"}})
	count(backup_tier_required.deny) == 0 with input as plan([r])
}

test_missing_tag_denied if {
	r := rc("aws_dynamodb_table", "aws_dynamodb_table.cell_map", {"tags_all": {"team": "platform"}})
	count(backup_tier_required.deny) == 1 with input as plan([r])
}

test_null_tags_denied if {
	r := rc("aws_ebs_volume", "aws_ebs_volume.bastion", {"tags": null, "tags_all": null})
	count(backup_tier_required.deny) == 1 with input as plan([r])
}

test_unknown_tier_denied if {
	r := rc("aws_ebs_volume", "aws_ebs_volume.bastion", {"tags_all": {"backup-tier": "platinum"}})
	count(backup_tier_required.deny) == 1 with input as plan([r])
}

test_bronze_ebs_allowed if {
	r := rc("aws_ebs_volume", "aws_ebs_volume.bastion", {"tags_all": {"backup-tier": "bronze"}})
	count(backup_tier_required.deny) == 0 with input as plan([r])
}

test_silver_aurora_below_minimum_denied if {
	r := rc("aws_rds_cluster", "aws_rds_cluster.cell0", {"tags_all": {"backup-tier": "silver"}})
	count(backup_tier_required.deny) == 1 with input as plan([r])
}

test_tag_on_default_tags_only_allowed if {
	r := rc("aws_memorydb_cluster", "aws_memorydb_cluster.cell0", {"tags": {}, "tags_all": {"backup-tier": "gold"}})
	count(backup_tier_required.deny) == 0 with input as plan([r])
}

test_stateless_resource_ignored if {
	r := rc("aws_lb", "aws_lb.api", {"tags_all": {}})
	count(backup_tier_required.deny) == 0 with input as plan([r])
}

test_deleted_resource_ignored if {
	r := {"type": "aws_ebs_volume", "address": "aws_ebs_volume.bastion", "change": {"actions": ["delete"], "after": null}}
	count(backup_tier_required.deny) == 0 with input as plan([r])
}

test_active_exception_allows if {
	r := rc("aws_ebs_volume", "aws_ebs_volume.scratch", {"tags_all": {}})
	ex := [{"rule": "terraform.backup_tier_required", "resource": "aws_ebs_volume.scratch", "owner": "platform", "reason": "test", "expires": "2200-12-31"}]
	count(backup_tier_required.deny) == 0 with input as plan([r]) with data.exceptions as ex
}
