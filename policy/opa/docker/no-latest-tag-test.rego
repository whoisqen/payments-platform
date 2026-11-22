package docker.no_latest_tag_test

import data.docker.no_latest_tag

digest := "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

from(value) := {"Cmd": "from", "Value": value, "StartLine": 1}

test_tagged_image_allowed if {
	count(no_latest_tag.deny) == 0 with input as [from(["rust:1.94.1-bookworm"])]
}

test_digest_pinned_image_allowed if {
	count(no_latest_tag.deny) == 0 with input as [from([concat("@", ["gcr.io/distroless/cc-debian12", digest])])]
}

test_latest_tag_denied if {
	count(no_latest_tag.deny) == 1 with input as [from(["rust:latest"])]
}

test_latest_tag_with_digest_denied if {
	count(no_latest_tag.deny) == 1 with input as [from([concat("@", ["rust:latest", digest])])]
}

test_untagged_image_denied if {
	count(no_latest_tag.deny) == 1 with input as [from(["rust"])]
}

test_registry_port_is_not_a_tag if {
	count(no_latest_tag.deny) == 1 with input as [from(["registry.example.com:5000/team/app"])]
}

test_scratch_allowed if {
	count(no_latest_tag.deny) == 0 with input as [from(["scratch"])]
}

test_earlier_stage_alias_allowed if {
	count(no_latest_tag.deny) == 0 with input as [from(["rust:1.94.1", "AS", "build"]), from(["build"])]
}

test_other_instruction_ignored if {
	count(no_latest_tag.deny) == 0 with input as [{"Cmd": "run", "Value": ["echo latest"]}]
}
