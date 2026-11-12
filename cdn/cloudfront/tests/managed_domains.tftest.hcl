################################################################################
# CloudFront Ravion-managed custom domain tests
################################################################################

mock_provider "aws" {
  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "123456789012"
    }
  }

  override_data {
    target = data.aws_region.current
    values = {
      id   = "us-east-1"
      name = "us-east-1"
    }
  }

  override_resource {
    target = aws_cloudfront_distribution.this
    values = {
      arn            = "arn:aws:cloudfront::123456789012:distribution/EBYOEXAMPLE"
      domain_name    = "dbyo.cloudfront.net"
      hosted_zone_id = "Z2FDTNDATAQYW2"
      id             = "EBYOEXAMPLE"
    }
  }

  override_resource {
    target = aws_cloudfront_distribution.managed
    values = {
      arn            = "arn:aws:cloudfront::123456789012:distribution/EMANAGEDEXAMPLE"
      domain_name    = "dmanaged.cloudfront.net"
      hosted_zone_id = "Z2FDTNDATAQYW2"
      id             = "EMANAGEDEXAMPLE"
    }
  }

  override_resource {
    target = aws_cloudwatch_log_group.access_logs
    values = {
      arn = "arn:aws:logs:us-east-1:123456789012:log-group:/aws/cloudfront/test-cf"
    }
  }

  override_resource {
    target = aws_cloudwatch_log_delivery_destination.access_logs
    values = {
      arn = "arn:aws:logs:us-east-1:123456789012:delivery-destination:test-cf-access-logs-cw"
    }
  }
}

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

variables {
  name                  = "test-cf"
  module_instance_id    = "minst_test"
  ravion_aws_account_id = "aws_testaccount"
  distributions = {
    primary = {
      managed_domains = [" www.Example.com. ", "example.com", "WWW.EXAMPLE.com."]
    }
  }
  origins = [
    {
      origin_id         = "s3-origin"
      domain_name       = "my-bucket.s3.us-east-1.amazonaws.com"
      s3_origin_enabled = true
    }
  ]
  default_cache_behavior = {
    target_origin_id       = "s3-origin"
    viewer_protocol_policy = "redirect-to-https"
  }
}

run "managed_domains_create_certificate_and_routing_records" {
  command = plan

  assert {
    condition     = length(ravion_aws_acm_certificate.this) == 1
    error_message = "A distribution with managed domains must get one certificate."
  }

  assert {
    condition     = ravion_aws_acm_certificate.this["primary"].aws_region == "us-east-1"
    error_message = "The certificate must be issued in us-east-1 for CloudFront."
  }

  assert {
    condition     = ravion_aws_acm_certificate.this["primary"].target_arn == "arn:aws:cloudfront::123456789012:distribution/EMANAGEDEXAMPLE"
    error_message = "The certificate must target the distribution ARN."
  }

  assert {
    condition     = toset(ravion_aws_acm_certificate.this["primary"].domains) == toset(["www.example.com", "example.com"])
    error_message = "The certificate must cover every managed domain."
  }

  assert {
    condition     = length(ravion_domain.this) == 2
    error_message = "Each managed domain must get one routing record."
  }

  assert {
    condition = alltrue([
      for d in ravion_domain.this :
      d.target_dns_name == "dmanaged.cloudfront.net" && d.target_zone_id == "Z2FDTNDATAQYW2"
    ])
    error_message = "Routing records must point at the distribution domain name and hosted zone."
  }

  assert {
    condition     = output.managed_primary_domains["primary"] == "www.example.com"
    error_message = "The first managed domain must be the primary domain."
  }

  assert {
    condition     = output.distribution_domains["primary"] == tolist(["www.example.com", "example.com"])
    error_message = "Viewer domains must use the normalized, deduplicated managed domains."
  }
}

run "managed_distribution_starts_with_default_certificate" {
  command = plan

  assert {
    condition     = length(aws_cloudfront_distribution.managed) == 1 && length(aws_cloudfront_distribution.this) == 0
    error_message = "A distribution with managed domains must use the managed resource only."
  }

  assert {
    condition     = length(aws_cloudfront_distribution.managed["primary"].aliases) == 0
    error_message = "The managed distribution must be created without aliases."
  }

  assert {
    condition     = aws_cloudfront_distribution.managed["primary"].viewer_certificate[0].cloudfront_default_certificate == true
    error_message = "The managed distribution must start with the default CloudFront certificate."
  }

  assert {
    condition     = output.distribution_arns["primary"] == "arn:aws:cloudfront::123456789012:distribution/EMANAGEDEXAMPLE"
    error_message = "Outputs must read managed distributions."
  }
}

run "byo_distribution_keeps_original_address" {
  command = plan

  variables {
    distributions = {
      primary = {
        aliases             = [" www.Example.com. ", "WWW.example.com", "api.EXAMPLE.com."]
        acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/11111111-1111-1111-1111-111111111111"
      }
    }
  }

  assert {
    condition     = length(aws_cloudfront_distribution.this) == 1 && length(aws_cloudfront_distribution.managed) == 0
    error_message = "A distribution without managed domains must stay at aws_cloudfront_distribution.this."
  }

  assert {
    condition     = toset(aws_cloudfront_distribution.this["primary"].aliases) == toset(["www.example.com", "api.example.com"])
    error_message = "BYO aliases must be normalized and deduplicated."
  }

  assert {
    condition     = output.distribution_domains["primary"] == tolist(["www.example.com", "api.example.com"])
    error_message = "Viewer domains must expose normalized BYO aliases."
  }

  assert {
    condition     = aws_cloudfront_distribution.this["primary"].viewer_certificate[0].acm_certificate_arn == "arn:aws:acm:us-east-1:123456789012:certificate/11111111-1111-1111-1111-111111111111"
    error_message = "The BYO certificate must still be set."
  }

  assert {
    condition     = length(ravion_aws_acm_certificate.this) == 0 && length(ravion_domain.this) == 0
    error_message = "BYO distributions must not create Ravion resources."
  }
}

run "mixed_distributions_split_between_resources" {
  command = plan

  variables {
    distributions = {
      byo = {
        aliases             = ["www.example.com"]
        acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/11111111-1111-1111-1111-111111111111"
      }
      ravion = {
        managed_domains = ["app.example.org"]
      }
    }
  }

  assert {
    condition     = length(aws_cloudfront_distribution.this) == 1 && length(aws_cloudfront_distribution.managed) == 1
    error_message = "Each distribution must land in the resource for its mode."
  }

  assert {
    condition     = length(output.distribution_ids) == 2
    error_message = "Outputs must include distributions from both resources."
  }

  assert {
    condition     = length(ravion_aws_acm_certificate.this) == 1 && contains(keys(ravion_aws_acm_certificate.this), "ravion")
    error_message = "Only the managed distribution gets a certificate."
  }
}

run "no_managed_domains_creates_no_ravion_resources" {
  command = plan

  variables {
    distributions = {
      primary = {}
    }
  }

  assert {
    condition     = length(ravion_aws_acm_certificate.this) == 0 && length(ravion_domain.this) == 0
    error_message = "Without managed domains no Ravion resources may be created."
  }

  assert {
    condition     = length(aws_cloudfront_distribution.managed) == 0
    error_message = "Without managed domains the managed resource stays empty."
  }

  assert {
    condition     = output.distribution_domains["primary"] == tolist([])
    error_message = "Without managed domains or aliases the viewer-domain output must be empty."
  }
}

run "managed_domains_reject_byo_aliases" {
  command = plan

  variables {
    distributions = {
      primary = {
        managed_domains = ["www.example.com"]
        aliases         = ["www.example.org"]
      }
    }
  }

  expect_failures = [
    var.distributions,
  ]
}

run "managed_domains_reject_byo_certificate" {
  command = plan

  variables {
    distributions = {
      primary = {
        managed_domains     = ["www.example.com"]
        acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/11111111-1111-1111-1111-111111111111"
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
      primary = {
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

run "managed_domains_reject_same_name_across_distributions" {
  command = plan

  variables {
    distributions = {
      primary = {
        managed_domains = ["WWW.Example.com"]
      }
      secondary = {
        managed_domains = [" www.example.com. "]
      }
    }
  }

  expect_failures = [
    var.distributions,
  ]
}

run "managed_domains_require_module_instance_id" {
  command = plan

  variables {
    module_instance_id = null
  }

  expect_failures = [
    ravion_aws_acm_certificate.this,
    ravion_domain.this,
  ]
}

run "apply_managed_distribution" {
  command = apply
}

run "managed_distribution_refuses_switch_to_byo" {
  command = plan

  variables {
    distributions = {
      primary = {
        aliases             = ["www.example.com"]
        acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/11111111-1111-1111-1111-111111111111"
      }
    }
  }

  expect_failures = [
    aws_cloudfront_distribution.this,
  ]
}

run "apply_byo_distribution" {
  command = apply

  variables {
    distributions = {
      site = {}
    }
  }
}

run "byo_distribution_refuses_switch_to_managed" {
  command = plan

  variables {
    distributions = {
      site = {
        managed_domains = ["www.example.com"]
      }
    }
  }

  expect_failures = [
    aws_cloudfront_distribution.managed,
  ]
}

run "new_distribution_alongside_byo_can_use_managed_domains" {
  command = plan

  variables {
    distributions = {
      site = {}
      next = {
        managed_domains = ["www.example.com"]
      }
    }
  }

  assert {
    condition     = length(aws_cloudfront_distribution.managed) == 1 && length(aws_cloudfront_distribution.this) == 1
    error_message = "A new managed distribution is added next to the existing one."
  }
}
