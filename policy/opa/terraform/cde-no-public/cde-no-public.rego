package terraform.cde_no_public

world := {"0.0.0.0/0", "::/0"}

# Deletes and no-ops are never judged.
changed(types) := {rc |
	some rc in input.resource_changes
	rc.type in types
	some action in rc.change.actions
	action in {"create", "update"}
}

after(rc) := rc.change.after

# The plan JSON has no account, so the CDE is recognised by the pci-scope and data-class tags (tags_all holds default_tags).
cde(rc) if after(rc).tags_all["pci-scope"] == "cde"

cde(rc) if after(rc).tags["pci-scope"] == "cde"

cde(rc) if after(rc).tags_all["data-class"] == "card-data"

excepted(rc) if {
	some e in data.exceptions
	e.rule == "terraform.cde_no_public"
	e.resource == rc.address
	time.parse_rfc3339_ns(concat("", [e.expires, "T23:59:59Z"])) >= time.now_ns()
}

deny contains msg if {
	some rc in changed({"aws_internet_gateway", "aws_egress_only_internet_gateway"})
	cde(rc)
	not excepted(rc)
	msg := sprintf("%v: an internet gateway is not allowed in the CDE", [rc.address])
}

deny contains msg if {
	some rc in changed({"aws_subnet"})
	cde(rc)
	after(rc).map_public_ip_on_launch == true
	not excepted(rc)
	msg := sprintf("%v: a public subnet is not allowed in the CDE", [rc.address])
}

deny contains msg if {
	some rc in changed({"aws_instance", "aws_launch_template", "aws_network_interface"})
	cde(rc)
	after(rc).associate_public_ip_address == true
	not excepted(rc)
	msg := sprintf("%v: a public IP is not allowed in the CDE", [rc.address])
}

deny contains msg if {
	some rc in changed({"aws_security_group"})
	cde(rc)
	some rule in after(rc).ingress
	some cidr in array.concat(object.get(rule, "cidr_blocks", []), object.get(rule, "ipv6_cidr_blocks", []))
	cidr in world
	not excepted(rc)
	msg := sprintf("%v: ingress from %v is not allowed in the CDE", [rc.address, cidr])
}

deny contains msg if {
	some rc in changed({"aws_vpc_security_group_ingress_rule"})
	cde(rc)
	some cidr in {object.get(after(rc), "cidr_ipv4", ""), object.get(after(rc), "cidr_ipv6", "")}
	cidr in world
	not excepted(rc)
	msg := sprintf("%v: ingress from %v is not allowed in the CDE", [rc.address, cidr])
}
