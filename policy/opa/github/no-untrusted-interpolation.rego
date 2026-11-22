package github.no_untrusted_interpolation

# Event payload fields and branch names are attacker-controlled; they must reach a script through env, never through the expression.
untrusted := `\$\{\{[^}]*(github\.event\.|github\.head_ref|github\.ref_name)`

scripts contains {"job": name, "text": step.run} if {
	some name, job in input.jobs
	some step in job.steps
	is_string(step.run)
}

scripts contains {"job": name, "text": step["with"].script} if {
	some name, job in input.jobs
	some step in job.steps
	startswith(step.uses, "actions/github-script@")
	is_string(step["with"].script)
}

deny contains msg if {
	some s in scripts
	regex.match(untrusted, s.text)
	msg := sprintf("job %v interpolates untrusted input in a script, pass it through env", [s.job])
}
