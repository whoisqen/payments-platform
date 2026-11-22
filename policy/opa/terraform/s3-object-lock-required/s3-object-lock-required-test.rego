package terraform.s3_object_lock_required_test

import data.terraform.s3_object_lock_required

rc(type, address, after) := {"type": type, "address": address, "change": {"actions": ["create"], "after": after}}

plan(changes) := {"resource_changes": changes}

test_gold_bucket_with_lock_allowed if {
	r := rc("aws_s3_bucket", "aws_s3_bucket.audit", {"tags_all": {"backup-tier": "gold"}, "object_lock_enabled": true})
	count(s3_object_lock_required.deny) == 0 with input as plan([r])
}

test_gold_bucket_without_lock_denied if {
	r := rc("aws_s3_bucket", "aws_s3_bucket.audit", {"tags_all": {"backup-tier": "gold"}, "object_lock_enabled": false})
	count(s3_object_lock_required.deny) == 1 with input as plan([r])
}

test_gold_bucket_lock_attribute_missing_denied if {
	r := rc("aws_s3_bucket", "aws_s3_bucket.audit", {"tags": null, "tags_all": {"backup-tier": "gold"}})
	count(s3_object_lock_required.deny) == 1 with input as plan([r])
}

test_bronze_bucket_without_lock_allowed if {
	r := rc("aws_s3_bucket", "aws_s3_bucket.scratch", {"tags_all": {"backup-tier": "bronze"}, "object_lock_enabled": false})
	count(s3_object_lock_required.deny) == 0 with input as plan([r])
}

test_default_retention_compliance_allowed if {
	r := rc("aws_s3_bucket_object_lock_configuration", "aws_s3_bucket_object_lock_configuration.audit", {"rule": [{"default_retention": [{"mode": "COMPLIANCE", "days": 365}]}]})
	count(s3_object_lock_required.deny) == 0 with input as plan([r])
}

test_default_retention_governance_years_allowed if {
	r := rc("aws_s3_bucket_object_lock_configuration", "aws_s3_bucket_object_lock_configuration.state", {"rule": [{"default_retention": [{"mode": "GOVERNANCE", "years": 1}]}]})
	count(s3_object_lock_required.deny) == 0 with input as plan([r])
}

test_lock_configuration_without_retention_denied if {
	r := rc("aws_s3_bucket_object_lock_configuration", "aws_s3_bucket_object_lock_configuration.audit", {"rule": []})
	count(s3_object_lock_required.deny) == 1 with input as plan([r])
}

test_zero_day_retention_denied if {
	r := rc("aws_s3_bucket_object_lock_configuration", "aws_s3_bucket_object_lock_configuration.audit", {"rule": [{"default_retention": [{"mode": "COMPLIANCE", "days": 0}]}]})
	count(s3_object_lock_required.deny) == 1 with input as plan([r])
}

test_deleted_bucket_ignored if {
	r := {"type": "aws_s3_bucket", "address": "aws_s3_bucket.audit", "change": {"actions": ["delete"], "after": null}}
	count(s3_object_lock_required.deny) == 0 with input as plan([r])
}

test_active_exception_allows if {
	r := rc("aws_s3_bucket", "aws_s3_bucket.legacy", {"tags_all": {"backup-tier": "gold"}, "object_lock_enabled": false})
	ex := [{"rule": "terraform.s3_object_lock_required", "resource": "aws_s3_bucket.legacy", "owner": "platform", "reason": "test", "expires": "2200-12-31"}]
	count(s3_object_lock_required.deny) == 0 with input as plan([r]) with data.exceptions as ex
}
