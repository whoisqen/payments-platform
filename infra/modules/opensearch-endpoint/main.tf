locals {
  name = "${var.name_prefix}-${var.env}-${var.region_short}-logs-endpoint"
}

resource "aws_security_group" "this" {
  name        = local.name
  description = "HTTPS to the central log domain through its VPC endpoint"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = local.name })
}

resource "aws_vpc_security_group_ingress_rule" "clients" {
  for_each = toset(var.client_cidr_blocks)

  security_group_id = aws_security_group.this.id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "HTTPS from the environment VPC"
}

# The domain stays in shared-services; requests still pass its access policy and fine-grained access control.
resource "aws_opensearch_vpc_endpoint" "this" {
  domain_arn = var.domain_arn

  vpc_options {
    subnet_ids         = var.subnet_ids
    security_group_ids = [aws_security_group.this.id]
  }
}
