package github.permissions_at_job_level

# The workflow level may only hold the read-only default; real grants live on the job that needs them.
workflow_default_ok if input.permissions == {}

workflow_default_ok if input.permissions == {"contents": "read"}

workflow_default_ok if not input.permissions

deny contains msg if {
	not workflow_default_ok
	msg := "workflow-level permissions must be absent, {} or contents: read"
}

deny contains msg if {
	some name, job in input.jobs
	not job.permissions
	msg := sprintf("job %v has no permissions block", [name])
}

deny contains msg if {
	some name, job in input.jobs
	job.permissions in {"write-all", "read-all"}
	msg := sprintf("job %v uses %v instead of explicit scopes", [name, job.permissions])
}
