package docker.distroless_test

import data.docker.distroless

from(value) := {"Cmd": "from", "Value": value, "StartLine": 1}

test_distroless_final_stage_allowed if {
	count(distroless.deny) == 0 with input as [from(["rust:1.94.1", "AS", "build"]), from(["gcr.io/distroless/cc-debian12:nonroot"])]
}

test_full_image_in_build_stage_allowed if {
	count(distroless.deny) == 0 with input as [from(["rust:1.94.1-bookworm", "AS", "build"]), from(["gcr.io/distroless/cc-debian12"])]
}

test_debian_final_stage_denied if {
	count(distroless.deny) == 1 with input as [from(["gcr.io/distroless/cc-debian12", "AS", "base"]), from(["debian:bookworm-slim"])]
}

test_single_stage_full_image_denied if {
	count(distroless.deny) == 1 with input as [from(["rust:1.94.1"])]
}

test_final_stage_from_build_alias_denied if {
	count(distroless.deny) == 1 with input as [from(["gcr.io/distroless/cc-debian12", "AS", "runtime"]), from(["runtime"])]
}
