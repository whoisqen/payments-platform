package terraform.required_tags_test

import data.terraform.required_tags

schema := {
	"environment": {"required": true, "values": ["dev", "stage", "prod"]},
	"owner": {"required": true, "pattern": "^[a-z0-9._-]+@[a-z0-9.-]+\\.[a-z]{2,}$"},
	"repo": {"required": true},
}

good := {"environment": "prod", "owner": "payments@example.com", "repo": "infra/modules/aurora"}

rc(address, after) := {"type": "aws_s3_bucket", "address": address, "change": {"actions": ["create"], "after": after, "after_unknown": {}}}

plan(changes) := {"resource_changes": changes}

test_complete_tags_allowed if {
	count(required_tags.deny) == 0 with input as plan([rc("aws_s3_bucket.a", {"tags_all": good})]) with data.tag_schema as schema
}

test_default_tags_merged_with_resource_tags if {
	r := rc("aws_s3_bucket.a", {"tags": {"repo": "infra/modules/aurora"}, "tags_all": {"environment": "prod", "owner": "payments@example.com", "repo": "infra/modules/aurora"}})
	count(required_tags.deny) == 0 with input as plan([r]) with data.tag_schema as schema
}

test_missing_tag_denied if {
	count(required_tags.deny) == 1 with input as plan([rc("aws_s3_bucket.a", {"tags_all": object.remove(good, ["repo"])})]) with data.tag_schema as schema
}

test_value_outside_schema_denied if {
	count(required_tags.deny) == 1 with input as plan([rc("aws_s3_bucket.a", {"tags_all": object.union(good, {"environment": "production"})})]) with data.tag_schema as schema
}

test_value_not_matching_pattern_denied if {
	count(required_tags.deny) == 1 with input as plan([rc("aws_s3_bucket.a", {"tags_all": object.union(good, {"owner": "not-an-address"})})]) with data.tag_schema as schema
}

test_empty_value_denied if {
	count(required_tags.deny) == 1 with input as plan([rc("aws_s3_bucket.a", {"tags_all": object.union(good, {"repo": ""})})]) with data.tag_schema as schema
}

test_resource_without_tag_support_ignored if {
	r := {"type": "aws_s3_bucket_policy", "address": "aws_s3_bucket_policy.a", "change": {"actions": ["create"], "after": {"policy": "{}"}}}
	count(required_tags.deny) == 0 with input as plan([r]) with data.tag_schema as schema
}

test_null_tags_denied if {
	count(required_tags.deny) == 3 with input as plan([rc("aws_s3_bucket.a", {"tags": null, "tags_all": null})]) with data.tag_schema as schema
}

test_deleted_resource_ignored if {
	r := {"type": "aws_s3_bucket", "address": "aws_s3_bucket.a", "change": {"actions": ["delete"], "after": null}}
	count(required_tags.deny) == 0 with input as plan([r]) with data.tag_schema as schema
}

test_active_exception_allows if {
	ex := [{"rule": "terraform.required_tags", "resource": "aws_s3_bucket.a", "owner": "platform", "reason": "test", "expires": "2200-12-31"}]
	count(required_tags.deny) == 0 with input as plan([rc("aws_s3_bucket.a", {"tags_all": {}})]) with data.tag_schema as schema with data.exceptions as ex
}

test_real_schema_accepts_a_fully_tagged_resource if {
	tags := {
		"environment": "prod", "team": "payments-core", "owner": "payments@example.com", "cost-center": "PAY-100",
		"cell": "cell-0", "component": "aurora", "pci-scope": "cde", "data-class": "card-data",
		"backup-tier": "gold", "managed-by": "terraform", "repo": "infra/modules/aurora",
	}
	count(required_tags.deny) == 0 with input as plan([rc("aws_s3_bucket.a", {"tags_all": tags})])
}
