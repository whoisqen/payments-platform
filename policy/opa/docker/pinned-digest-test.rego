package docker.pinned_digest_test

import data.docker.pinned_digest

digest := "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

from(value) := {"Cmd": "from", "Value": value, "StartLine": 1}

test_pinned_image_allowed if {
	count(pinned_digest.deny) == 0 with input as [from([concat("@", ["rust:1.94.1", digest])])]
}

test_tag_only_denied if {
	count(pinned_digest.deny) == 1 with input as [from(["rust:1.94.1"])]
}

test_short_digest_denied if {
	count(pinned_digest.deny) == 1 with input as [from(["rust:1.94.1@sha256:0123"])]
}

test_unresolved_variable_denied if {
	count(pinned_digest.deny) == 1 with input as [from(["${BASE_IMAGE}"])]
}

test_scratch_allowed if {
	count(pinned_digest.deny) == 0 with input as [from(["scratch"])]
}

test_earlier_stage_alias_allowed if {
	count(pinned_digest.deny) == 0 with input as [from([concat("@", ["rust:1.94.1", digest]), "AS", "build"]), from(["build"])]
}

test_every_stage_is_checked if {
	count(pinned_digest.deny) == 1 with input as [from([concat("@", ["rust:1.94.1", digest]), "AS", "build"]), from(["gcr.io/distroless/cc-debian12"])]
}
