package config.pci_pack_lint

# Run as: opa test policy/config/pci-dss-pack; the YAML loads as data.Resources.
must_have := {
	"CLOUD_TRAIL_ENABLED",
	"EC2_IMDSV2_CHECK",
	"GUARDDUTY_ENABLED_CENTRALIZED",
	"S3_BUCKET_LEVEL_PUBLIC_ACCESS_PROHIBITED",
	"ENCRYPTED_VOLUMES",
	"RDS_STORAGE_ENCRYPTED",
	"IAM_ROOT_ACCESS_KEY_CHECK",
	"REQUIRED_TAGS",
	"DYNAMODB_PITR_ENABLED",
	"S3_BUCKET_DEFAULT_LOCK_ENABLED",
}

identifiers := [r.Properties.Source.SourceIdentifier | some r in data.Resources]

deny contains msg if {
	some id, r in data.Resources
	r.Type != "AWS::Config::ConfigRule"
	msg := sprintf("%v: type must be AWS::Config::ConfigRule", [id])
}

deny contains msg if {
	some id, r in data.Resources
	not startswith(r.Properties.ConfigRuleName, "pci-")
	msg := sprintf("%v: ConfigRuleName must start with pci-", [id])
}

deny contains msg if {
	some id, r in data.Resources
	not regex.match(`^PCI DSS [0-9]+\.[0-9]+(\.[0-9]+)* `, object.get(r.Properties, "Description", ""))
	msg := sprintf("%v: Description must start with the PCI DSS requirement", [id])
}

deny contains msg if {
	some id, r in data.Resources
	r.Properties.Source.Owner != "AWS"
	msg := sprintf("%v: the PCI pack holds managed rules only, custom rules live in custom-rules", [id])
}

deny contains msg if {
	some id, r in data.Resources
	not regex.match(`^[A-Z0-9_]+$`, r.Properties.Source.SourceIdentifier)
	msg := sprintf("%v: SourceIdentifier is not an upper-case managed rule identifier", [id])
}

deny contains msg if {
	some id in identifiers
	count([x | some x in identifiers; x == id]) > 1
	msg := sprintf("%v is declared twice", [id])
}

deny contains msg if {
	some id in must_have
	not id in identifiers
	msg := sprintf("managed rule %v is missing", [id])
}
