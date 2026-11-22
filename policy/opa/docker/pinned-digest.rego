package docker.pinned_digest

# Conftest parses a Dockerfile into a flat list of instructions with a lower-case Cmd.
stage_aliases contains lower(i.Value[2]) if {
	some i in input
	i.Cmd == "from"
	lower(i.Value[1]) == "as"
}

# The digest is of the manifest list so that arm64 and amd64 resolve the same reference.
deny contains msg if {
	some i in input
	i.Cmd == "from"
	image := i.Value[0]
	lower(image) != "scratch"
	not lower(image) in stage_aliases
	not regex.match(`@sha256:[a-f0-9]{64}$`, image)
	msg := sprintf("line %v: FROM %v is not pinned by a sha256 digest", [object.get(i, "StartLine", 0), image])
}
