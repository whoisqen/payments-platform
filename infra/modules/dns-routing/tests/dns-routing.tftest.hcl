mock_provider "aws" {}

variables {
  zone_id     = "Z0123456789ABCDEFGHIJ"
  record_name = "api.stage.pay.example.com"
  endpoints = {
    euc1 = { region = "eu-central-1", target_dns = "api-euc1.stage.pay.example.com" }
    use1 = { region = "us-east-1", target_dns = "api-use1.stage.pay.example.com" }
  }
}

run "latency_records_with_https_checks" {
  command = plan

  assert {
    condition     = length(aws_route53_record.this) == 2 && length(aws_route53_health_check.this) == 2
    error_message = "one latency record and one health check per endpoint"
  }

  assert {
    condition     = aws_route53_record.this["use1"].latency_routing_policy[0].region == "us-east-1" && aws_route53_record.this["euc1"].latency_routing_policy[0].region == "eu-central-1"
    error_message = "latency region equals the input region"
  }

  assert {
    condition     = alltrue([for h in values(aws_route53_health_check.this) : h.type == "HTTPS"])
    error_message = "health checks are HTTPS"
  }
}

run "bad_region_rejected" {
  command = plan

  variables {
    endpoints = {
      euc1 = { region = "EU", target_dns = "api-euc1.stage.pay.example.com" }
      use1 = { region = "us-east-1", target_dns = "api-use1.stage.pay.example.com" }
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
