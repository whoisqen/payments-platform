mock_provider "aws" {}

variables {
  zone_id     = "Z0123456789ABCDEFGHIJ"
  record_name = "api.stage.pay.example.com"
  primary_key = "euc1"
  endpoints = {
    euc1 = { target_dns = "api-euc1.stage.pay.example.com" }
    use1 = { target_dns = "api-use1.stage.pay.example.com" }
  }
}

run "primary_and_secondary_with_https_checks" {
  command = plan

  assert {
    condition     = length(aws_route53_record.this) == 2 && length(aws_route53_health_check.this) == 2
    error_message = "one failover record and one health check per endpoint"
  }

  assert {
    condition     = aws_route53_record.this["euc1"].failover_routing_policy[0].type == "PRIMARY" && aws_route53_record.this["use1"].failover_routing_policy[0].type == "SECONDARY"
    error_message = "the working region is the primary, the other region the secondary"
  }

  assert {
    condition     = alltrue([for h in values(aws_route53_health_check.this) : h.type == "HTTPS"])
    error_message = "health checks are HTTPS"
  }
}

run "unknown_primary_rejected" {
  command = plan

  variables {
    primary_key = "apse1"
  }

  expect_failures = [var.primary_key]
}

run "three_endpoints_rejected" {
  command = plan

  variables {
    endpoints = {
      euc1  = { target_dns = "a.example.com" }
      use1  = { target_dns = "b.example.com" }
      third = { target_dns = "c.example.com" }
    }
  }

  expect_failures = [var.endpoints]
}

run "bad_interval_rejected" {
  command = plan

  variables {
    request_interval = 15
  }

  expect_failures = [var.request_interval]
}
