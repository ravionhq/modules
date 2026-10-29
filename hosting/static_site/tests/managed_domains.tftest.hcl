################################################################################
# hosting/static_site - Ravion-managed custom domain tests
################################################################################

mock_provider "ravion" {
  mock_resource "ravion_domain" {
    defaults = {
      id = "domain_test"
    }
  }

  mock_resource "ravion_aws_acm_certificate" {
    defaults = {
      id     = "cert_test"
      arn    = "arn:aws:acm:us-east-1:123456789012:certificate/99999999-9999-9999-9999-999999999999"
      status = "ISSUED"
    }
  }
}

mock_provider "aws" {
  override_data {
    target = data.aws_iam_policy_document.hosting_bucket_policy
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.deploy_role_policy
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

# CloudFront distribution, KVS, CloudFront Functions, and the optional
# response-headers policy all run through the us_east_1 alias. Their resource
# overrides live here so apply-mode tests don't hit the real CloudFront API
# and so resource arns are deterministic.
mock_provider "aws" {
  alias = "us_east_1"

  # Mock providers do not derive computed regions from provider configuration.
  # Set this only on the alias so the assertion detects incorrect provider wiring.
  mock_resource "aws_cloudwatch_metric_alarm" {
    defaults = {
      region = "us-east-1"
    }
  }

  override_resource {
    target = aws_cloudfront_function.rewrite
    values = {
      arn = "arn:aws:cloudfront::123456789012:function/test-rewrite"
    }
  }

  override_resource {
    target = aws_cloudfront_function.cache_control
    values = {
      arn = "arn:aws:cloudfront::123456789012:function/test-cache-control"
    }
  }

  override_resource {
    target = aws_cloudfront_key_value_store.this
    values = {
      arn = "arn:aws:cloudfront::123456789012:key-value-store/12345678-1234-1234-1234-123456789012"
      id  = "12345678-1234-1234-1234-123456789012"
    }
  }

  override_resource {
    target = aws_cloudfront_response_headers_policy.this
    values = {
      id = "module-rh-policy-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    }
  }

  override_resource {
    target = aws_cloudfront_cache_policy.this
    values = {
      id = "module-cache-policy-11111111-2222-3333-4444-555555555555"
    }
  }

  # The delivery-source and delivery-destination resources validate their ARN
  # attributes at plan time, so mocked upstream ARNs must be well-formed.
  override_resource {
    target = module.cdn.aws_cloudfront_distribution.this
    values = {
      arn            = "arn:aws:cloudfront::123456789012:distribution/E2EXAMPLE123"
      domain_name    = "dbyo.cloudfront.net"
      hosted_zone_id = "Z2FDTNDATAQYW2"
    }
  }

  override_resource {
    target = module.cdn.aws_cloudfront_distribution.managed
    values = {
      arn            = "arn:aws:cloudfront::123456789012:distribution/EMANAGED123"
      domain_name    = "dmanaged.cloudfront.net"
      hosted_zone_id = "Z2FDTNDATAQYW2"
    }
  }

  override_resource {
    target = module.cdn.aws_cloudwatch_log_group.access_logs
    values = {
      arn = "arn:aws:logs:us-east-1:123456789012:log-group:/aws/cloudfront/ravion-test-site"
    }
  }

  override_resource {
    target = module.cdn.aws_cloudwatch_log_delivery_destination.access_logs
    values = {
      arn = "arn:aws:logs:us-east-1:123456789012:delivery-destination:ravion-test-site-access-logs-cw"
    }
  }
}

variables {
  name                  = "test-site"
  region                = "us-west-2"
  module_instance_id    = "minst_test"
  ravion_aws_account_id = "aws_testaccount"
}

run "managed_domains_issue_certificate_and_prefer_first_domain" {
  command = plan

  variables {
    distributions = {
      main = {
        managed_domains = [" app.Example.com. ", "www.example.com", "APP.EXAMPLE.com."]
      }
    }
  }

  assert {
    condition     = keys(module.cdn.managed_certificate_arns) == ["main"]
    error_message = "Managed domains must create one certificate for the distribution."
  }

  assert {
    condition     = length(module.cdn.managed_domain_records["main"]) == 2 && alltrue([for r in module.cdn.managed_domain_records["main"] : r.type == "CNAME" && r.value == "dmanaged.cloudfront.net"])
    error_message = "Each managed domain must get a routing record pointing at the distribution."
  }

  assert {
    condition     = output.primary_domain == "app.example.com" && output.distribution_primary_domains["main"] == "app.example.com"
    error_message = "The first managed domain must be the primary domain."
  }

  assert {
    condition     = output.domains == tolist(["app.example.com", "www.example.com"])
    error_message = "The output must expose normalized and deduplicated managed domains."
  }
}

run "byo_aliases_unchanged" {
  command = plan

  variables {
    distributions = {
      main = {
        aliases             = ["www.example.com"]
        acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/11111111-1111-1111-1111-111111111111"
      }
    }
  }

  assert {
    condition     = length(module.cdn.managed_certificate_arns) == 0 && output.primary_domain == "www.example.com"
    error_message = "BYO aliases must not create Ravion resources and stay the primary domain."
  }

  assert {
    condition     = output.domains == tolist(["www.example.com"])
    error_message = "The output must expose the configured BYO aliases."
  }
}

run "distribution_domains_normalize_aliases" {
  command = plan

  variables {
    distributions = {
      main = {
        aliases             = [" www.Example.com. ", "WWW.example.com", "assets.EXAMPLE.org."]
        acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/11111111-1111-1111-1111-111111111111"
      }
    }
  }

  assert {
    condition     = output.domains == tolist(["www.example.com", "assets.example.org"])
    error_message = "The output must expose normalized and deduplicated BYO aliases."
  }
}

run "default_distribution_has_no_managed_resources" {
  command = plan

  assert {
    condition     = length(module.cdn.managed_certificate_arns) == 0 && output.primary_domain == "dbyo.cloudfront.net"
    error_message = "Without custom domains the CloudFront domain name stays the primary domain."
  }

  assert {
    condition     = output.domains == tolist([])
    error_message = "Without custom domains the viewer-domain output must be empty."
  }
}

run "managed_domains_reject_byo_aliases" {
  command = plan

  variables {
    distributions = {
      main = {
        managed_domains = ["app.example.com"]
        aliases         = ["www.example.com"]
      }
    }
  }

  expect_failures = [
    var.distributions,
  ]
}

run "managed_domains_reject_more_than_ten" {
  command = plan

  variables {
    distributions = {
      main = {
        managed_domains = [
          "app0.example.com",
          "app1.example.com",
          "app2.example.com",
          "app3.example.com",
          "app4.example.com",
          "app5.example.com",
          "app6.example.com",
          "app7.example.com",
          "app8.example.com",
          "app9.example.com",
          "app10.example.com",
        ]
      }
    }
  }

  expect_failures = [
    var.distributions,
  ]
}
