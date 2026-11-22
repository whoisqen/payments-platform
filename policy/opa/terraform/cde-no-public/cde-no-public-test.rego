package terraform.cde_no_public_test

import data.terraform.cde_no_public

cde_tags := {"pci-scope": "cde", "data-class": "card-data"}

other_tags := {"pci-scope": "out-of-scope", "data-class": "internal"}

rc(type, address, after) := {"type": type, "address": address, "change": {"actions": ["create"], "after": after}}

plan(changes) := {"resource_changes": changes}

test_cde_internet_gateway_denied if {
	count(cde_no_public.deny) == 1 with input as plan([rc("aws_internet_gateway", "aws_internet_gateway.main", {"tags_all": cde_tags})])
}

test_non_cde_internet_gateway_allowed if {
	count(cde_no_public.deny) == 0 with input as plan([rc("aws_internet_gateway", "aws_internet_gateway.main", {"tags_all": other_tags})])
}

test_cde_public_subnet_denied if {
	count(cde_no_public.deny) == 1 with input as plan([rc("aws_subnet", "aws_subnet.a", {"tags_all": cde_tags, "map_public_ip_on_launch": true})])
}

test_cde_private_subnet_allowed if {
	count(cde_no_public.deny) == 0 with input as plan([rc("aws_subnet", "aws_subnet.a", {"tags_all": cde_tags, "map_public_ip_on_launch": false})])
}

test_cde_public_ip_denied if {
	count(cde_no_public.deny) == 1 with input as plan([rc("aws_instance", "aws_instance.bastion", {"tags": cde_tags, "associate_public_ip_address": true})])
}

test_cde_security_group_open_ingress_denied if {
	sg := rc("aws_security_group", "aws_security_group.router", {"tags_all": cde_tags, "ingress": [{"cidr_blocks": ["0.0.0.0/0"], "ipv6_cidr_blocks": []}]})
	count(cde_no_public.deny) == 1 with input as plan([sg])
}

test_cde_security_group_ipv6_open_ingress_denied if {
	sg := rc("aws_security_group", "aws_security_group.router", {"tags_all": cde_tags, "ingress": [{"cidr_blocks": [], "ipv6_cidr_blocks": ["::/0"]}]})
	count(cde_no_public.deny) == 1 with input as plan([sg])
}

test_cde_security_group_internal_ingress_allowed if {
	sg := rc("aws_security_group", "aws_security_group.router", {"tags_all": cde_tags, "ingress": [{"cidr_blocks": ["10.100.0.0/16"], "ipv6_cidr_blocks": []}]})
	count(cde_no_public.deny) == 0 with input as plan([sg])
}

test_cde_ingress_rule_open_denied if {
	r := rc("aws_vpc_security_group_ingress_rule", "aws_vpc_security_group_ingress_rule.https", {"tags_all": cde_tags, "cidr_ipv4": "0.0.0.0/0"})
	count(cde_no_public.deny) == 1 with input as plan([r])
}

test_cde_ingress_rule_internal_allowed if {
	r := rc("aws_vpc_security_group_ingress_rule", "aws_vpc_security_group_ingress_rule.https", {"tags_all": cde_tags, "cidr_ipv4": "10.100.0.0/16"})
	count(cde_no_public.deny) == 0 with input as plan([r])
}

test_deleted_cde_internet_gateway_ignored if {
	gw := {"type": "aws_internet_gateway", "address": "aws_internet_gateway.main", "change": {"actions": ["delete"], "after": null}}
	count(cde_no_public.deny) == 0 with input as plan([gw])
}

test_active_exception_allows if {
	gw := rc("aws_internet_gateway", "aws_internet_gateway.main", {"tags_all": cde_tags})
	ex := [{"rule": "terraform.cde_no_public", "resource": "aws_internet_gateway.main", "owner": "platform", "reason": "test", "expires": "2200-12-31"}]
	count(cde_no_public.deny) == 0 with input as plan([gw]) with data.exceptions as ex
}

test_expired_exception_does_not_allow if {
	gw := rc("aws_internet_gateway", "aws_internet_gateway.main", {"tags_all": cde_tags})
	ex := [{"rule": "terraform.cde_no_public", "resource": "aws_internet_gateway.main", "owner": "platform", "reason": "test", "expires": "2000-01-01"}]
	count(cde_no_public.deny) == 1 with input as plan([gw]) with data.exceptions as ex
}
