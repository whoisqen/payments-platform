package terraform.iam_no_wildcard_test

import data.terraform.iam_no_wildcard

rc(type, address, after) := {"type": type, "address": address, "change": {"actions": ["create"], "after": after}}

plan(changes) := {"resource_changes": changes}

policy_rc(doc) := rc("aws_iam_policy", "aws_iam_policy.p", {"policy": json.marshal(doc)})

scoped := {"Version": "2012-10-17", "Statement": [{"Effect": "Allow", "Action": ["s3:GetObject"], "Resource": "arn:aws:s3:::payments-artifacts/*"}]}

test_scoped_policy_allowed if {
	count(iam_no_wildcard.deny) == 0 with input as plan([policy_rc(scoped)])
}

test_wildcard_action_denied if {
	doc := {"Version": "2012-10-17", "Statement": [{"Effect": "Allow", "Action": "*", "Resource": "arn:aws:s3:::payments-artifacts/*"}]}
	count(iam_no_wildcard.deny) == 1 with input as plan([policy_rc(doc)])
}

test_wildcard_action_in_list_denied if {
	doc := {"Version": "2012-10-17", "Statement": [{"Effect": "Allow", "Action": ["s3:GetObject", "*"], "Resource": "arn:aws:s3:::payments-artifacts/*"}]}
	count(iam_no_wildcard.deny) == 1 with input as plan([policy_rc(doc)])
}

test_wildcard_resource_denied if {
	doc := {"Version": "2012-10-17", "Statement": {"Effect": "Allow", "Action": ["iam:PassRole"], "Resource": "*"}}
	count(iam_no_wildcard.deny) == 1 with input as plan([policy_rc(doc)])
}

test_not_action_allow_denied if {
	doc := {"Version": "2012-10-17", "Statement": [{"Effect": "Allow", "NotAction": ["iam:*"], "Resource": "arn:aws:s3:::payments-artifacts/*"}]}
	count(iam_no_wildcard.deny) == 1 with input as plan([policy_rc(doc)])
}

test_deny_statement_with_wildcards_allowed if {
	doc := {"Version": "2012-10-17", "Statement": [{"Effect": "Deny", "Action": "*", "Resource": "*"}]}
	count(iam_no_wildcard.deny) == 0 with input as plan([policy_rc(doc)])
}

test_inline_role_policy_checked if {
	inline := {"Version": "2012-10-17", "Statement": [{"Effect": "Allow", "Action": "*", "Resource": "*"}]}
	r := rc("aws_iam_role", "aws_iam_role.r", {"inline_policy": [{"name": "x", "policy": json.marshal(inline)}]})
	count(iam_no_wildcard.deny) == 2 with input as plan([r])
}

test_policy_known_after_apply_is_skipped if {
	r := {"type": "aws_iam_policy", "address": "aws_iam_policy.p", "change": {"actions": ["create"], "after": {}}}
	count(iam_no_wildcard.deny) == 0 with input as plan([r])
}

test_deleted_policy_ignored if {
	r := {"type": "aws_iam_policy", "address": "aws_iam_policy.p", "change": {"actions": ["delete"], "after": null}}
	count(iam_no_wildcard.deny) == 0 with input as plan([r])
}

test_active_exception_allows if {
	doc := {"Version": "2012-10-17", "Statement": [{"Effect": "Allow", "Action": ["ecr:GetAuthorizationToken"], "Resource": "*"}]}
	ex := [{"rule": "terraform.iam_no_wildcard", "resource": "aws_iam_policy.p", "owner": "platform", "reason": "ecr login has no resource scope", "expires": "2200-12-31"}]
	count(iam_no_wildcard.deny) == 0 with input as plan([policy_rc(doc)]) with data.exceptions as ex
}

test_expired_exception_does_not_allow if {
	doc := {"Version": "2012-10-17", "Statement": [{"Effect": "Allow", "Action": ["ecr:GetAuthorizationToken"], "Resource": "*"}]}
	ex := [{"rule": "terraform.iam_no_wildcard", "resource": "aws_iam_policy.p", "owner": "platform", "reason": "test", "expires": "2000-01-01"}]
	count(iam_no_wildcard.deny) == 1 with input as plan([policy_rc(doc)]) with data.exceptions as ex
}
