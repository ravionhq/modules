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
      arn            = "arn:aws:cloudfront::123456789012:distribution/EEXAMPLE"
      domain_name    = "dexample.cloudfront.net"
      hosted_zone_id = "Z2FDTNDATAQYW2"
      id             = "EEXAMPLE"
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
    condition     = ravion_aws_acm_certificate.this["primary"].target_arn == "arn:aws:cloudfront::123456789012:distribution/EEXAMPLE"
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
      d.target_dns_name == "dexample.cloudfront.net" && d.target_zone_id == "Z2FDTNDATAQYW2"
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
    condition     = length(aws_cloudfront_distribution.this) == 1
    error_message = "A distribution with managed domains must use the one distribution resource."
  }

  assert {
    condition     = length(aws_cloudfront_distribution.this["primary"].aliases) == 0
    error_message = "The managed distribution must be created without aliases."
  }

  assert {
    condition     = aws_cloudfront_distribution.this["primary"].viewer_certificate[0].cloudfront_default_certificate == true
    error_message = "The managed distribution must start with the default CloudFront certificate."
  }

  assert {
    condition     = length(ravion_aws_cloudfront_viewer_certificate.this) == 0
    error_message = "Ravion attaches a managed distribution's certificate, so Terraform must not set one."
  }

  assert {
    condition     = output.distribution_arns["primary"] == "arn:aws:cloudfront::123456789012:distribution/EEXAMPLE"
    error_message = "Outputs must read managed distributions."
  }
}

run "byo_distribution_sets_its_own_certificate" {
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
    condition     = toset(aws_cloudfront_distribution.this["primary"].aliases) == toset(["www.example.com", "api.example.com"])
    error_message = "A new BYO distribution must be created with its normalized, deduplicated aliases."
  }

  assert {
    condition     = toset(ravion_aws_cloudfront_viewer_certificate.this["primary"].aliases) == toset(["www.example.com", "api.example.com"])
    error_message = "The viewer certificate resource must own the normalized BYO aliases."
  }

  assert {
    condition     = ravion_aws_cloudfront_viewer_certificate.this["primary"].acm_certificate_arn == "arn:aws:acm:us-east-1:123456789012:certificate/11111111-1111-1111-1111-111111111111"
    error_message = "The viewer certificate resource must own the BYO certificate."
  }

  assert {
    condition     = ravion_aws_cloudfront_viewer_certificate.this["primary"].distribution_id == "EEXAMPLE"
    error_message = "The viewer certificate resource must target the distribution."
  }

  assert {
    condition     = ravion_aws_cloudfront_viewer_certificate.this["primary"].minimum_protocol_version == "TLSv1.2_2021" && ravion_aws_cloudfront_viewer_certificate.this["primary"].ssl_support_method == "sni-only"
    error_message = "The viewer certificate resource must carry the module's TLS settings."
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

run "mixed_distributions_share_one_resource" {
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
    condition     = length(aws_cloudfront_distribution.this) == 2
    error_message = "Both distributions must live in the one distribution resource."
  }

  assert {
    condition     = keys(ravion_aws_cloudfront_viewer_certificate.this) == ["byo"]
    error_message = "Only the BYO distribution gets a viewer certificate resource."
  }

  assert {
    condition     = length(output.distribution_ids) == 2
    error_message = "Outputs must include both distributions."
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
    condition     = length(ravion_aws_cloudfront_viewer_certificate.this["primary"].aliases) == 0 && ravion_aws_cloudfront_viewer_certificate.this["primary"].acm_certificate_arn == null
    error_message = "Without aliases the distribution must serve the default certificate."
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

run "managed_distribution_switches_to_byo_in_place" {
  command = apply

  variables {
    distributions = {
      primary = {
        aliases             = ["www.example.com"]
        acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/11111111-1111-1111-1111-111111111111"
      }
    }
  }

  assert {
    condition     = keys(aws_cloudfront_distribution.this) == ["primary"]
    error_message = "The distribution must stay where it is when it leaves managed domains."
  }

  assert {
    condition     = toset(ravion_aws_cloudfront_viewer_certificate.this["primary"].aliases) == toset(["www.example.com"]) && ravion_aws_cloudfront_viewer_certificate.this["primary"].distribution_id == "EEXAMPLE"
    error_message = "The BYO aliases and certificate must be set on the same distribution."
  }

  assert {
    condition     = length(ravion_aws_acm_certificate.this) == 0 && length(ravion_domain.this) == 0
    error_message = "Leaving managed domains must remove the Ravion certificate and routing records."
  }
}

run "apply_byo_distribution" {
  command = apply

  variables {
    distributions = {
      site = {}
    }
  }
}

run "byo_distribution_switches_to_managed_in_place" {
  command = plan

  variables {
    distributions = {
      site = {
        managed_domains = ["www.example.com"]
      }
    }
  }

  assert {
    condition     = keys(aws_cloudfront_distribution.this) == ["site"] && length(ravion_aws_cloudfront_viewer_certificate.this) == 0
    error_message = "The distribution must stay where it is and hand its aliases and certificate to Ravion."
  }

  assert {
    condition     = ravion_aws_acm_certificate.this["site"].target_arn == "arn:aws:cloudfront::123456789012:distribution/EEXAMPLE"
    error_message = "The Ravion certificate must attach to the existing distribution."
  }
}
