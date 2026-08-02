# Managed-domain listener integration tests.
#
# The ALB child module must keep owning HTTPS listeners, SNI attachments, and
# security-group rules. Managed mode changes only the certificate list passed
# into that existing module, preserving every released Terraform address.

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

  override_data {
    target = data.aws_ssm_parameter.ecs_optimized_ami
    values = {
      value = "ami-0123456789abcdef0"
    }
  }

  override_data {
    target = data.aws_elb_service_account.current
    values = {
      arn = "arn:aws:iam::127311923021:root"
    }
  }

  override_resource {
    target = module.public_alb.aws_lb.this
    values = {
      arn        = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/test-public-alb/1234567890123456"
      arn_suffix = "app/test-public-alb/1234567890123456"
      dns_name   = "test-public-alb-123456789.us-east-1.elb.amazonaws.com"
      zone_id    = "Z35SXDOTRQ7X7K"
    }
  }

  override_resource {
    target = module.public_alb.aws_lb_listener.https
    values = {
      arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/test-public-alb/1234567890123456/6543210987654321"
    }
  }

  override_resource {
    target = module.public_alb.aws_security_group.this
    values = {
      arn = "arn:aws:ec2:us-east-1:123456789012:security-group/sg-publicalb123456"
      id  = "sg-publicalb123456"
    }
  }

  override_resource {
    target = module.private_alb.aws_lb.this
    values = {
      arn        = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/test-private-alb/1234567890123457"
      arn_suffix = "app/test-private-alb/1234567890123457"
      dns_name   = "test-private-alb-123456789.us-east-1.elb.amazonaws.com"
      zone_id    = "Z35SXDOTRQ7X7K"
    }
  }

  override_resource {
    target = module.private_alb.aws_lb_listener.https
    values = {
      arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/test-private-alb/1234567890123457/6543210987654322"
    }
  }

  override_resource {
    target = module.private_alb.aws_security_group.this
    values = {
      arn = "arn:aws:ec2:us-east-1:123456789012:security-group/sg-privatealb123456"
      id  = "sg-privatealb123456"
    }
  }
}

mock_provider "ravion" {
  override_resource {
    target = ravion_aws_acm_certificate.cluster
    values = {
      id          = "cert_test"
      arn         = "arn:aws:acm:us-east-1:123456789012:certificate/99999999-9999-9999-9999-999999999999"
      domain_name = "test-cluster-abcd.ravion.app"
      status      = "ISSUED"
    }
  }
}

variables {
  name               = "test-cluster"
  module_instance_id = "minst_test"
  vpc_id             = "vpc-12345678"
  private_subnet_ids = ["subnet-private1", "subnet-private2"]
  public_subnet_ids  = ["subnet-public1", "subnet-public2"]
}

run "byo_public_listener_keeps_released_address" {
  command = plan

  variables {
    public_alb_enabled          = true
    public_alb_https_enabled    = true
    public_alb_certificate_arns = ["arn:aws:acm:us-east-1:123456789012:certificate/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"]
  }

  assert {
    condition     = module.public_alb[0].https_listener_arn != null
    error_message = "The existing ALB child module must own the public HTTPS listener"
  }

  assert {
    condition     = module.public_alb[0].https_listener_certificate_arn == "arn:aws:acm:us-east-1:123456789012:certificate/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    error_message = "BYO mode must keep the customer's first certificate as the listener default"
  }

  assert {
    condition     = output.public_alb_https_listener_arn == module.public_alb[0].https_listener_arn
    error_message = "The public listener output must continue to expose the child-module listener"
  }
}

run "managed_public_swaps_certificate_in_place" {
  command = plan

  variables {
    public_alb_enabled         = true
    public_alb_https_enabled   = true
    use_ravion_managed_domains = true
    ravion_aws_account_id      = "aws_testaccount"
  }

  assert {
    condition     = length(ravion_aws_acm_certificate.cluster) == 1
    error_message = "Managed mode must create one wildcard certificate"
  }

  assert {
    condition     = module.public_alb[0].https_listener_certificate_arn == ravion_aws_acm_certificate.cluster[0].arn
    error_message = "Managed mode must swap the existing child listener to the Ravion certificate"
  }

  assert {
    condition     = ravion_aws_acm_certificate.cluster[0].target_dns_name == module.public_alb[0].alb_dns_name
    error_message = "The managed wildcard DNS target must be the selected public ALB"
  }
}

run "managed_toggle_keeps_byo_certificates_attached" {
  command = plan

  variables {
    public_alb_enabled         = true
    public_alb_https_enabled   = true
    use_ravion_managed_domains = true
    ravion_aws_account_id      = "aws_testaccount"
    public_alb_certificate_arns = [
      "arn:aws:acm:us-east-1:123456789012:certificate/byo-default",
      "arn:aws:acm:us-east-1:123456789012:certificate/byo-extra",
    ]
  }

  # The wildcard becomes the DEFAULT certificate...
  assert {
    condition     = module.public_alb[0].https_listener_certificate_arn == ravion_aws_acm_certificate.cluster[0].arn
    error_message = "Managed mode must make the Ravion wildcard the default certificate"
  }

  # ...and every BYO certificate stays attached via SNI, so hostnames served
  # off them keep their TLS through and after the migration.
  assert {
    condition     = length(module.public_alb[0].additional_certificate_arns) == 2
    error_message = "Both BYO certificates must remain attached via SNI in managed mode"
  }

  assert {
    condition     = contains(module.public_alb[0].additional_certificate_arns, "arn:aws:acm:us-east-1:123456789012:certificate/byo-default") && contains(module.public_alb[0].additional_certificate_arns, "arn:aws:acm:us-east-1:123456789012:certificate/byo-extra")
    error_message = "The SNI set must contain exactly the BYO certificates"
  }
}

run "managed_private_uses_existing_listener" {
  command = plan

  variables {
    private_alb_enabled        = true
    private_alb_https_enabled  = true
    use_ravion_managed_domains = true
    ravion_aws_account_id      = "aws_testaccount"
  }

  assert {
    condition     = module.private_alb[0].https_listener_certificate_arn == ravion_aws_acm_certificate.cluster[0].arn
    error_message = "Managed mode must use the existing private ALB listener"
  }

  assert {
    condition     = ravion_aws_acm_certificate.cluster[0].target_dns_name == module.private_alb[0].alb_dns_name
    error_message = "The managed wildcard DNS target must be the selected private ALB"
  }
}

run "managed_domains_rejects_both_albs" {
  command = plan

  variables {
    public_alb_enabled         = true
    public_alb_https_enabled   = true
    private_alb_enabled        = true
    private_alb_https_enabled  = true
    use_ravion_managed_domains = true
    ravion_aws_account_id      = "aws_testaccount"
  }

  expect_failures = [ravion_aws_acm_certificate.cluster]
}

run "managed_domains_requires_https" {
  command = plan

  variables {
    public_alb_enabled         = true
    public_alb_https_enabled   = false
    use_ravion_managed_domains = true
    ravion_aws_account_id      = "aws_testaccount"
  }

  expect_failures = [ravion_aws_acm_certificate.cluster]
}

run "managed_domains_requires_an_alb" {
  command = plan

  variables {
    use_ravion_managed_domains = true
    ravion_aws_account_id      = "aws_testaccount"
  }

  expect_failures = [ravion_aws_acm_certificate.cluster]
}
