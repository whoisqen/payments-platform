package config.custom_lint

# Run as: opa test policy/config/custom-rules; the YAML loads as data.Resources. Guard text itself is not evaluated here.
deny contains msg if {
	some id, r in data.Resources
	r.Type != "AWS::Config::ConfigRule"
	msg := sprintf("%v: type must be AWS::Config::ConfigRule", [id])
}

deny contains msg if {
	some id, r in data.Resources
	not startswith(r.Properties.ConfigRuleName, "platform-")
	msg := sprintf("%v: ConfigRuleName must start with platform-", [id])
}

deny contains msg if {
	some id, r in data.Resources
	r.Properties.Source.Owner != "CUSTOM_POLICY"
	msg := sprintf("%v: custom rules use the Guard runtime (CUSTOM_POLICY)", [id])
}

deny contains msg if {
	some id, r in data.Resources
	not startswith(r.Properties.Source.CustomPolicyDetails.PolicyRuntime, "guard-2.")
	msg := sprintf("%v: PolicyRuntime must be guard-2.x.x", [id])
}

deny contains msg if {
	some id, r in data.Resources
	not regex.match(`rule [a-z_]+`, object.get(r.Properties.Source.CustomPolicyDetails, "PolicyText", ""))
	msg := sprintf("%v: PolicyText holds no Guard rule", [id])
}

deny contains msg if {
	some id, r in data.Resources
	count(object.get(object.get(r.Properties, "Scope", {}), "ComplianceResourceTypes", [])) == 0
	msg := sprintf("%v: scope the rule to resource types", [id])
}

deny contains msg if {
	some id, r in data.Resources
	some t in r.Properties.Scope.ComplianceResourceTypes
	not regex.match(`^AWS::[A-Za-z0-9]+::[A-Za-z0-9]+$`, t)
	msg := sprintf("%v: %v is not a resource type", [id, t])
}

# The enumerated values in the tag rule must stay equal to the schema, so every value is checked against this list.
schema_values := {
	"environment": ["dev", "stage", "prod"],
	"pci-scope": ["cde", "connected", "out-of-scope"],
	"data-class": ["card-data", "pii", "internal", "public"],
	"backup-tier": ["gold", "silver", "bronze", "none"],
	"managed-by": ["terraform", "argocd", "aft"],
}

deny contains msg if {
	some key, values in schema_values
	text := data.Resources.TagSchema.Properties.Source.CustomPolicyDetails.PolicyText
	expected := sprintf("tags.\"%v\" in [%v]", [key, concat(", ", [sprintf("\"%v\"", [v]) | some v in values])])
	not contains(text, expected)
	msg := sprintf("TagSchema does not enforce %v values %v", [key, values])
}
