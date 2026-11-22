package docker.no_latest_tag

# Conftest parses a Dockerfile into a flat list of instructions with a lower-case Cmd.
stage_aliases contains lower(i.Value[2]) if {
	some i in input
	i.Cmd == "from"
	lower(i.Value[1]) == "as"
}

external_froms contains i if {
	some i in input
	i.Cmd == "from"
	lower(i.Value[0]) != "scratch"
	not lower(i.Value[0]) in stage_aliases
}

name_part(image) := split(image, "@")[0]

last_segment(image) := regex.split("/", name_part(image))[count(regex.split("/", name_part(image))) - 1]

has_tag(image) if contains(last_segment(image), ":")

tag(image) := split(last_segment(image), ":")[1]

deny contains msg if {
	some i in external_froms
	image := i.Value[0]
	not has_tag(image)
	not contains(image, "@")
	msg := sprintf("line %v: %v has no tag, which means latest", [object.get(i, "StartLine", 0), image])
}

deny contains msg if {
	some i in external_froms
	image := i.Value[0]
	has_tag(image)
	tag(image) == "latest"
	msg := sprintf("line %v: %v uses the latest tag", [object.get(i, "StartLine", 0), image])
}
