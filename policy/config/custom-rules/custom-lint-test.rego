package config.custom_lint_test

import data.config.custom_lint

good := {
	"Type": "AWS::Config::ConfigRule",
	"Properties": {
		"ConfigRuleName": "platform-x",
		"Scope": {"ComplianceResourceTypes": ["AWS::S3::Bucket"]},
		"Source": {"Owner": "CUSTOM_POLICY", "CustomPolicyDetails": {"PolicyRuntime": "guard-2.x.x", "PolicyText": "rule x { a == 1 }"}},
	},
}

test_committed_rules_are_clean if {
	count(custom_lint.deny) == 0
}

test_wrong_resource_type_denied if {
	some msg in custom_lint.deny with data.Resources as {"X": object.union(good, {"Type": "AWS::S3::Bucket"})}
	contains(msg, "type must be")
}

test_missing_prefix_denied if {
	bad := object.union(good, {"Properties": object.union(good.Properties, {"ConfigRuleName": "x"})})
	some msg in custom_lint.deny with data.Resources as {"X": bad}
	contains(msg, "must start with platform-")
}

test_managed_source_denied if {
	src := object.union(good.Properties.Source, {"Owner": "AWS"})
	bad := object.union(good, {"Properties": object.union(good.Properties, {"Source": src})})
	some msg in custom_lint.deny with data.Resources as {"X": bad}
	contains(msg, "CUSTOM_POLICY")
}

test_text_without_rule_denied if {
	details := object.union(good.Properties.Source.CustomPolicyDetails, {"PolicyText": "nothing"})
	src := object.union(good.Properties.Source, {"CustomPolicyDetails": details})
	bad := object.union(good, {"Properties": object.union(good.Properties, {"Source": src})})
	some msg in custom_lint.deny with data.Resources as {"X": bad}
	contains(msg, "holds no Guard rule")
}

test_unscoped_rule_denied if {
	bad := object.union(good, {"Properties": object.union(good.Properties, {"Scope": {"ComplianceResourceTypes": []}})})
	some msg in custom_lint.deny with data.Resources as {"X": bad}
	contains(msg, "scope the rule")
}

test_tag_rule_with_a_changed_value_list_denied if {
	text := "rule tag_schema { tags.\"backup-tier\" in [\"gold\"] }"
	details := object.union(good.Properties.Source.CustomPolicyDetails, {"PolicyText": text})
	src := object.union(good.Properties.Source, {"CustomPolicyDetails": details})
	bad := object.union(good, {"Properties": object.union(good.Properties, {"Source": src})})
	some msg in custom_lint.deny with data.Resources as {"TagSchema": bad}
	contains(msg, "TagSchema does not enforce backup-tier")
}
