package docker.distroless

# Conftest parses a Dockerfile into a flat list of instructions with a lower-case Cmd.
froms := [i | some i in input; i.Cmd == "from"]

# Only the last stage ships, so build stages may use full images.
final := froms[count(froms) - 1]

deny contains msg if {
	not contains(lower(final.Value[0]), "distroless")
	msg := sprintf("line %v: the final stage must be based on a distroless image, not %v", [object.get(final, "StartLine", 0), final.Value[0]])
}
