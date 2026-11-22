package github.id_token_aws_only_test

import data.github.id_token_aws_only

aws_step := {"uses": "aws-actions/configure-aws-credentials@0123456789abcdef0123456789abcdef01234567"}

test_aws_job_with_id_token_allowed if {
	wf := {"jobs": {"plan": {"permissions": {"id-token": "write", "contents": "read"}, "steps": [aws_step, {"run": "make plan"}]}}}
	count(id_token_aws_only.deny) == 0 with input as wf
}

test_job_without_id_token_allowed if {
	wf := {"jobs": {"lint": {"permissions": {"contents": "read"}, "steps": [{"run": "make lint"}]}}}
	count(id_token_aws_only.deny) == 0 with input as wf
}

test_id_token_without_aws_step_denied if {
	wf := {"jobs": {"lint": {"permissions": {"id-token": "write"}, "steps": [{"run": "make lint"}]}}}
	count(id_token_aws_only.deny) == 1 with input as wf
}

test_id_token_with_only_other_action_denied if {
	wf := {"jobs": {"lint": {"permissions": {"id-token": "write"}, "steps": [{"uses": "actions/checkout@0123456789abcdef0123456789abcdef01234567"}]}}}
	count(id_token_aws_only.deny) == 1 with input as wf
}

test_workflow_level_id_token_denied if {
	wf := {"permissions": {"id-token": "write"}, "jobs": {"plan": {"permissions": {"id-token": "write"}, "steps": [aws_step]}}}
	count(id_token_aws_only.deny) == 1 with input as wf
}

test_id_token_read_is_not_a_grant if {
	wf := {"jobs": {"lint": {"permissions": {"id-token": "none"}, "steps": [{"run": "make lint"}]}}}
	count(id_token_aws_only.deny) == 0 with input as wf
}
