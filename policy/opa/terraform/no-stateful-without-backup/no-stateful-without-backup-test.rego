package terraform.no_stateful_without_backup_test

import data.terraform.no_stateful_without_backup

rc(type, address, after) := {"type": type, "address": address, "change": {"actions": ["create"], "after": after}}

plan(changes) := {"resource_changes": changes}

aurora := {"tags_all": {"backup-tier": "gold"}, "backup_retention_period": 35}

table := {"tags_all": {"backup-tier": "gold"}, "point_in_time_recovery": [{"enabled": true}]}

test_covered_aurora_allowed if {
	count(no_stateful_without_backup.deny) == 0 with input as plan([rc("aws_rds_cluster", "aws_rds_cluster.cell0", aurora)])
}

test_aurora_without_tier_denied if {
	r := rc("aws_rds_cluster", "aws_rds_cluster.cell0", {"tags_all": {}, "backup_retention_period": 35})
	count(no_stateful_without_backup.deny) == 1 with input as plan([r])
}

test_aurora_tier_none_denied if {
	r := rc("aws_rds_cluster", "aws_rds_cluster.cell0", object.union(aurora, {"tags_all": {"backup-tier": "none"}}))
	count(no_stateful_without_backup.deny) == 1 with input as plan([r])
}

test_aurora_short_retention_denied if {
	r := rc("aws_rds_cluster", "aws_rds_cluster.cell0", object.union(aurora, {"backup_retention_period": 7}))
	count(no_stateful_without_backup.deny) == 1 with input as plan([r])
}

test_covered_dynamodb_allowed if {
	count(no_stateful_without_backup.deny) == 0 with input as plan([rc("aws_dynamodb_table", "aws_dynamodb_table.cell_map", table)])
}

test_dynamodb_without_pitr_denied if {
	r := rc("aws_dynamodb_table", "aws_dynamodb_table.cell_map", object.union(table, {"point_in_time_recovery": [{"enabled": false}]}))
	count(no_stateful_without_backup.deny) == 1 with input as plan([r])
}

test_dynamodb_without_pitr_block_denied if {
	r := rc("aws_dynamodb_table", "aws_dynamodb_table.cell_map", {"tags_all": {"backup-tier": "gold"}, "point_in_time_recovery": []})
	count(no_stateful_without_backup.deny) == 1 with input as plan([r])
}

test_s3_bucket_without_tier_denied if {
	count(no_stateful_without_backup.deny) == 1 with input as plan([rc("aws_s3_bucket", "aws_s3_bucket.state", {"tags": null, "tags_all": null})])
}

test_bronze_ebs_allowed if {
	count(no_stateful_without_backup.deny) == 0 with input as plan([rc("aws_ebs_volume", "aws_ebs_volume.bastion", {"tags_all": {"backup-tier": "bronze"}})])
}

test_stateless_resource_ignored if {
	count(no_stateful_without_backup.deny) == 0 with input as plan([rc("aws_lb", "aws_lb.api", {"tags_all": {}})])
}

test_deleted_resource_ignored if {
	r := {"type": "aws_rds_cluster", "address": "aws_rds_cluster.cell0", "change": {"actions": ["delete"], "after": null}}
	count(no_stateful_without_backup.deny) == 0 with input as plan([r])
}

test_active_exception_allows if {
	r := rc("aws_ebs_volume", "aws_ebs_volume.scratch", {"tags_all": {"backup-tier": "none"}})
	ex := [{"rule": "terraform.no_stateful_without_backup", "resource": "aws_ebs_volume.scratch", "owner": "platform", "reason": "no data", "expires": "2200-12-31"}]
	count(no_stateful_without_backup.deny) == 0 with input as plan([r]) with data.exceptions as ex
}

test_expired_exception_does_not_allow if {
	r := rc("aws_ebs_volume", "aws_ebs_volume.scratch", {"tags_all": {"backup-tier": "none"}})
	ex := [{"rule": "terraform.no_stateful_without_backup", "resource": "aws_ebs_volume.scratch", "owner": "platform", "reason": "no data", "expires": "2000-01-01"}]
	count(no_stateful_without_backup.deny) == 1 with input as plan([r]) with data.exceptions as ex
}
