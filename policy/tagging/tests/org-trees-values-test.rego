package tagging.org_trees_test

# Run as: opa test policy/tagging; the management and security live trees tag with values outside the workload environments.
# Without schema.yaml the positive checks are vacuous, so a run of the tests directory alone stays green.
loaded if data.tag_schema

allowed(key, value) if value in data.tag_schema[key].values

management_stack := {"environment": "management", "component": "org-policies", "cell": "shared"}

security_stacks := [
	{"environment": "security", "component": "log-archive", "cell": "shared"},
	{"environment": "security", "component": "org-config", "cell": "shared"},
	{"environment": "security", "component": "org-security-services", "cell": "shared"},
]

all_allowed(tags) if {
	every key, value in tags {
		allowed(key, value)
	}
}

management_ok if {
	loaded
	all_allowed(management_stack)
}

management_ok if not loaded

security_ok if not loaded

security_ok if {
	loaded
	every tags in security_stacks {
		all_allowed(tags)
	}
}

components_ok if not loaded

components_ok if {
	loaded
	every c in ["org-policies", "org-trail", "org-security-services", "org-config"] {
		allowed("component", c)
	}
}

test_management_stack_tags_are_allowed if management_ok

test_security_stack_tags_are_allowed if security_ok

test_management_components_are_allowed if components_ok

test_abbreviated_environment_is_denied if not allowed("environment", "mgmt")

test_audit_is_not_an_environment if not allowed("environment", "audit")

test_unlisted_org_component_is_denied if not allowed("component", "org-anything")

test_org_wildcard_is_not_a_value if not allowed("component", "org-*")

test_new_environments_are_not_components if {
	not allowed("component", "management")
	not allowed("component", "security")
}
