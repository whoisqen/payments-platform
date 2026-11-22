package tagging.sync_test

# Run as: opa test policy/tagging policy/scp/tag-policies; the Organizations tag policy must say what schema.yaml says.
# Without both data files the checks are vacuous, so a run of this directory alone stays green.
loaded if {
	data.tag_schema
	data.tags
}

with_values := {k | some k, spec in data.tag_schema; spec.values}

free_form := {k | some k, spec in data.tag_schema; not spec.values}

same_keys if not loaded

same_keys if {
	{k | some k, _ in data.tags} == {k | some k, _ in data.tag_schema}
}

same_values if not loaded

same_values if {
	every k in with_values {
		data.tag_schema[k].values == data.tags[k].tag_value["@@assign"]
	}
}

no_values_for_free_form if not loaded

no_values_for_free_form if {
	every k in free_form {
		not data.tags[k].tag_value
	}
}

all_required if not loaded

all_required if {
	every _, spec in data.tag_schema {
		spec.required == true
	}
}

test_tag_policy_covers_exactly_the_schema_keys if same_keys

test_tag_policy_values_match_the_schema if same_values

test_free_form_tags_have_no_values_in_the_tag_policy if no_values_for_free_form

test_every_schema_key_is_required if all_required
