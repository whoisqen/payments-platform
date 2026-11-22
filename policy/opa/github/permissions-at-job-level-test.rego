package github.permissions_at_job_level_test

import data.github.permissions_at_job_level

test_job_level_permissions_allowed if {
	wf := {"permissions": {"contents": "read"}, "jobs": {"lint": {"permissions": {"contents": "read"}, "steps": []}}}
	count(permissions_at_job_level.deny) == 0 with input as wf
}

test_absent_workflow_permissions_allowed if {
	count(permissions_at_job_level.deny) == 0 with input as {"jobs": {"lint": {"permissions": {}, "steps": []}}}
}

test_job_without_permissions_denied if {
	wf := {"permissions": {"contents": "read"}, "jobs": {"lint": {"steps": []}}}
	count(permissions_at_job_level.deny) == 1 with input as wf
}

test_workflow_level_write_denied if {
	wf := {"permissions": {"contents": "write"}, "jobs": {"lint": {"permissions": {"contents": "read"}, "steps": []}}}
	count(permissions_at_job_level.deny) == 1 with input as wf
}

test_write_all_denied if {
	wf := {"jobs": {"lint": {"permissions": "write-all", "steps": []}}}
	count(permissions_at_job_level.deny) == 1 with input as wf
}

test_every_job_is_checked if {
	wf := {"jobs": {"a": {"permissions": {}}, "b": {"steps": []}, "c": {"steps": []}}}
	count(permissions_at_job_level.deny) == 2 with input as wf
}
