package config.pci_pack_lint_test

import data.config.pci_pack_lint

rule(name, desc, id) := {"Type": "AWS::Config::ConfigRule", "Properties": {"ConfigRuleName": name, "Description": desc, "Source": {"Owner": "AWS", "SourceIdentifier": id}}}

test_committed_pack_is_clean if {
	count(pci_pack_lint.deny) == 0
}

test_wrong_resource_type_denied if {
	bad := {"A": object.union(rule("pci-a", "PCI DSS 1.1.1 x", "A_ID"), {"Type": "AWS::S3::Bucket"})}
	some msg in pci_pack_lint.deny with data.Resources as bad
	contains(msg, "type must be")
}

test_missing_prefix_denied if {
	bad := {"A": rule("a", "PCI DSS 1.1.1 x", "A_ID")}
	some msg in pci_pack_lint.deny with data.Resources as bad
	contains(msg, "must start with pci-")
}

test_description_without_requirement_denied if {
	bad := {"A": rule("pci-a", "some words", "A_ID")}
	some msg in pci_pack_lint.deny with data.Resources as bad
	contains(msg, "Description")
}

test_custom_source_denied if {
	bad := {"A": object.union(rule("pci-a", "PCI DSS 1.1.1 x", "A_ID"), {"Properties": {"ConfigRuleName": "pci-a", "Description": "PCI DSS 1.1.1 x", "Source": {"Owner": "CUSTOM_POLICY", "SourceIdentifier": "A_ID"}}})}
	some msg in pci_pack_lint.deny with data.Resources as bad
	contains(msg, "managed rules only")
}

test_duplicate_identifier_denied if {
	bad := {"A": rule("pci-a", "PCI DSS 1.1.1 x", "A_ID"), "B": rule("pci-b", "PCI DSS 1.1.1 x", "A_ID")}
	some msg in pci_pack_lint.deny with data.Resources as bad
	contains(msg, "declared twice")
}

test_missing_must_have_rule_denied if {
	bad := {"A": rule("pci-a", "PCI DSS 1.1.1 x", "A_ID")}
	some msg in pci_pack_lint.deny with data.Resources as bad
	contains(msg, "CLOUD_TRAIL_ENABLED is missing")
}
