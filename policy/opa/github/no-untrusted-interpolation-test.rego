package github.no_untrusted_interpolation_test

import data.github.no_untrusted_interpolation

wf(step) := {"jobs": {"build": {"permissions": {}, "steps": [step]}}}

test_env_indirection_allowed if {
	step := {"env": {"TITLE": "${{ github.event.pull_request.title }}"}, "run": "echo \"$TITLE\""}
	count(no_untrusted_interpolation.deny) == 0 with input as wf(step)
}

test_trusted_expression_allowed if {
	count(no_untrusted_interpolation.deny) == 0 with input as wf({"run": "echo ${{ github.sha }} ${{ runner.os }} ${{ github.event_name }}"})
}

test_event_field_in_run_denied if {
	count(no_untrusted_interpolation.deny) == 1 with input as wf({"run": "echo ${{ github.event.pull_request.title }}"})
}

test_head_ref_in_run_denied if {
	count(no_untrusted_interpolation.deny) == 1 with input as wf({"run": "git checkout ${{ github.head_ref }}"})
}

test_ref_name_in_run_denied if {
	count(no_untrusted_interpolation.deny) == 1 with input as wf({"run": "echo ${{ github.ref_name }}"})
}

test_event_field_in_github_script_denied if {
	step := {"uses": "actions/github-script@0123456789abcdef0123456789abcdef01234567", "with": {"script": "console.log(`${{ github.event.issue.body }}`)"}}
	count(no_untrusted_interpolation.deny) == 1 with input as wf(step)
}

test_step_without_run_ignored if {
	count(no_untrusted_interpolation.deny) == 0 with input as wf({"uses": "actions/checkout@0123456789abcdef0123456789abcdef01234567"})
}
