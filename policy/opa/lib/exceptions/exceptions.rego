package lib.exceptions

# The expiry day counts until 23:59:59 UTC.
expires_ns(e) := time.parse_rfc3339_ns(concat("", [e.expires, "T23:59:59Z"]))

required := {"rule", "resource", "owner", "reason", "expires"}

# Conftest runs this namespace against policy/exceptions.yaml, so an expired entry breaks CI.
deny contains msg if {
	some e in data.exceptions
	expires_ns(e) < time.now_ns()
	msg := sprintf("exception for %v on %v expired on %v", [e.rule, e.resource, e.expires])
}

deny contains msg if {
	some i, e in data.exceptions
	some field in required
	not e[field]
	msg := sprintf("exception %d has no %v", [i, field])
}
