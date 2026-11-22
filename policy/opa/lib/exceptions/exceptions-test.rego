package lib.exceptions_test

import data.lib.exceptions

valid := {
	"rule": "terraform.iam_no_wildcard",
	"resource": "aws_iam_policy.ecr_login",
	"owner": "platform",
	"reason": "ecr:GetAuthorizationToken has no resource scope",
	"expires": "2200-12-31",
}

test_valid_exception_is_clean if {
	count(exceptions.deny) == 0 with data.exceptions as [valid]
}

test_expired_exception_fails_ci if {
	old := object.union(valid, {"expires": "2000-01-01"})
	count(exceptions.deny) == 1 with data.exceptions as [old]
}

test_missing_owner_fails_ci if {
	broken := object.remove(valid, ["owner"])
	count(exceptions.deny) == 1 with data.exceptions as [broken]
}

test_empty_list_is_clean if {
	count(exceptions.deny) == 0 with data.exceptions as []
}

test_committed_exception_file_is_clean if {
	count(exceptions.deny) == 0
}
