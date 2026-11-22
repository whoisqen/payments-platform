package terraform.iam_no_wildcard

policy_types := {"aws_iam_policy", "aws_iam_role_policy", "aws_iam_user_policy", "aws_iam_group_policy"}

# Deletes and no-ops are never judged.
changed(types) := {rc |
	some rc in input.resource_changes
	rc.type in types
	some action in rc.change.actions
	action in {"create", "update"}
}

excepted(rc) if {
	some e in data.exceptions
	e.rule == "terraform.iam_no_wildcard"
	e.resource == rc.address
	time.parse_rfc3339_ns(concat("", [e.expires, "T23:59:59Z"])) >= time.now_ns()
}

# The policy attribute is a JSON string; a policy known only after apply cannot be parsed here.
documents contains {"rc": rc, "doc": json.unmarshal(rc.change.after.policy)} if {
	some rc in changed(policy_types)
	is_string(rc.change.after.policy)
}

documents contains {"rc": rc, "doc": json.unmarshal(inline.policy)} if {
	some rc in changed({"aws_iam_role"})
	some inline in rc.change.after.inline_policy
	is_string(inline.policy)
}

statements(doc) := [doc.Statement] if is_object(doc.Statement)

statements(doc) := doc.Statement if is_array(doc.Statement)

as_list(x) := x if is_array(x)

as_list(x) := [x] if is_string(x)

allow_statements contains {"rc": d.rc, "st": st} if {
	some d in documents
	some st in statements(d.doc)
	st.Effect == "Allow"
}

deny contains msg if {
	some s in allow_statements
	"*" in as_list(s.st.Action)
	not excepted(s.rc)
	msg := sprintf("%v: Allow with Action \"*\"", [s.rc.address])
}

deny contains msg if {
	some s in allow_statements
	s.st.NotAction
	not excepted(s.rc)
	msg := sprintf("%v: Allow with NotAction grants every other action", [s.rc.address])
}

deny contains msg if {
	some s in allow_statements
	"*" in as_list(s.st.Resource)
	not excepted(s.rc)
	msg := sprintf("%v: Allow with Resource \"*\"", [s.rc.address])
}
