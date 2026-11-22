package github.id_token_aws_only

aws_login := "aws-actions/configure-aws-credentials@"

# An OIDC token is a credential, so only a job that signs in to AWS may mint one.
signs_in_to_aws(job) if {
	some step in job.steps
	startswith(step.uses, aws_login)
}

deny contains msg if {
	input.permissions["id-token"] == "write"
	msg := "workflow-level id-token: write is not allowed, grant it on the AWS job"
}

deny contains msg if {
	some name, job in input.jobs
	job.permissions["id-token"] == "write"
	not signs_in_to_aws(job)
	msg := sprintf("job %v has id-token: write but no %v step", [name, aws_login])
}
