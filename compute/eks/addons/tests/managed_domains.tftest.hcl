# Managed-domain listener integration tests for the shared ALBs.
#
# The ALB child module keeps owning HTTPS listeners, SNI attachments and
# security-group rules. Managed mode changes only the certificate list passed
# into that existing module, so toggling it is an in-place default-certificate
# swap, never a listener replacement. Mirrors compute/ecs_cluster's coverage.

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com" }
  }
  mock_data "aws_region" {
    defaults = { region = "us-east-2" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_eks_cluster" {
    defaults = {
      arn                   = "arn:aws:eks:us-east-2:123456789012:cluster/test-cluster"
      endpoint              = "https://mock.eks.amazonaws.com"
      certificate_authority = [{ data = "bW9jay1jYQ==" }]
      vpc_config = [{
        vpc_id                    = "vpc-12345678"
        cluster_security_group_id = "sg-12345678"
        control_plane_egress_mode = ""
        endpoint_private_access   = true
        endpoint_public_access    = false
        public_access_cidrs       = []
        security_group_ids        = []
        subnet_ids                = []
      }]
    }
  }
  # Listeners validate the load balancer ARN they are handed.
  mock_resource "aws_lb" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-east-2:123456789012:loadbalancer/app/mock/0123456789abcdef" }
  }
  # SNI certificate attachments validate the listener ARN they are handed.
  mock_resource "aws_lb_listener" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-east-2:123456789012:listener/app/mock/0123456789abcdef/fedcba9876543210" }
  }

  override_resource {
    target = module.public_alb.aws_lb.this
    values = {
      arn      = "arn:aws:elasticloadbalancing:us-east-2:123456789012:loadbalancer/app/test-cluster-pub/1234567890123456"
      dns_name = "test-cluster-pub-123456789.us-east-2.elb.amazonaws.com"
      zone_id  = "Z3AADJGX6KTTL2"
    }
  }
  override_resource {
    target = module.private_alb.aws_lb.this
    values = {
      arn      = "arn:aws:elasticloadbalancing:us-east-2:123456789012:loadbalancer/app/test-cluster-priv/1234567890123457"
      dns_name = "internal-test-cluster-priv-123456789.us-east-2.elb.amazonaws.com"
      zone_id  = "Z3AADJGX6KTTL2"
    }
  }
}
mock_provider "helm" {}

mock_provider "ravion" {
  override_resource {
    target = ravion_aws_acm_certificate.cluster
    values = {
      id          = "cert_test"
      arn         = "arn:aws:acm:us-east-2:123456789012:certificate/99999999-9999-9999-9999-999999999999"
      domain_name = "test-cluster-abcd.example-apex.test"
      status      = "ISSUED"
    }
  }
}

variables {
  traces_destinations                  = []
  ebs_csi_driver_enabled               = false
  cluster_name                         = "test-cluster"
  module_instance_id                   = "minst_test"
  region                               = "us-east-2"
  cluster_security_group_id            = "sg-12345678"
  public_subnet_ids                    = ["subnet-0a", "subnet-0b"]
  node_subnet_ids                      = ["subnet-1a", "subnet-1b"]
  karpenter_enabled                    = false
  eso_enabled                          = false
  logs_providers                       = []
  metrics_providers                    = []
  ravion_operator_enabled              = false
  aws_load_balancer_controller_enabled = false
}

run "managed_domains_off_by_default" {
  command = plan

  variables {
    public_alb_creation_enabled = true
    public_alb_https_enabled    = true
    public_alb_certificate_arns = ["arn:aws:acm:us-east-2:123456789012:certificate/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"]
  }

  assert {
    condition     = length(ravion_aws_acm_certificate.cluster) == 0
    error_message = "No Ravion certificate may be issued unless use_ravion_managed_domains is on"
  }

  assert {
    condition     = module.public_alb[0].https_listener_certificate_arn == "arn:aws:acm:us-east-2:123456789012:certificate/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    error_message = "BYO mode must keep the caller's first certificate as the listener default"
  }

  assert {
    condition     = output.ravion_managed_domains_enabled == false && output.ravion_cluster_domain_fqdn == null && output.ravion_cluster_cert_arn == null
    error_message = "Managed-domain outputs must be off/null when the feature is disabled"
  }
}

run "managed_public_swaps_certificate_in_place" {
  command = plan

  variables {
    public_alb_creation_enabled = true
    public_alb_https_enabled    = true
    use_ravion_managed_domains  = true
    ravion_aws_account_id       = "aws_testaccount"
  }

  assert {
    condition     = length(ravion_aws_acm_certificate.cluster) == 1 && ravion_aws_acm_certificate.cluster[0].wildcard == true
    error_message = "Managed mode must create exactly one wildcard certificate"
  }

  assert {
    condition     = ravion_aws_acm_certificate.cluster[0].name == "test-cluster" && ravion_aws_acm_certificate.cluster[0].module_instance_id == "minst_test" && ravion_aws_acm_certificate.cluster[0].aws_account_id == "aws_testaccount" && ravion_aws_acm_certificate.cluster[0].aws_region == "us-east-2"
    error_message = "The wildcard leaf must default to the name slug and carry the module instance, account and region"
  }

  assert {
    condition     = module.public_alb[0].https_listener_certificate_arn == ravion_aws_acm_certificate.cluster[0].arn
    error_message = "Managed mode must swap the existing public listener's default certificate to the Ravion certificate"
  }

  assert {
    condition     = ravion_aws_acm_certificate.cluster[0].target_dns_name == module.public_alb[0].alb_dns_name && ravion_aws_acm_certificate.cluster[0].target_zone_id == module.public_alb[0].alb_zone_id
    error_message = "The wildcard ALIAS target must be the selected public ALB"
  }

  assert {
    condition     = output.ravion_managed_domains_enabled == true && output.ravion_cluster_domain_fqdn == "test-cluster-abcd.example-apex.test" && output.ravion_cluster_cert_arn == ravion_aws_acm_certificate.cluster[0].arn && output.ravion_aws_region == "us-east-2"
    error_message = "Managed-domain outputs must expose the apex, cert ARN and region"
  }

  assert {
    condition     = output.public_alb_arn != null && output.public_alb_https_listener_arn != null && output.public_alb_security_group_id != null
    error_message = "The public ALB ARN, HTTPS listener ARN and security group id must be exposed for routing consumers"
  }
}

run "managed_toggle_keeps_byo_certificates_attached" {
  command = plan

  variables {
    public_alb_creation_enabled = true
    public_alb_https_enabled    = true
    use_ravion_managed_domains  = true
    ravion_aws_account_id       = "aws_testaccount"
    public_alb_certificate_arns = [
      "arn:aws:acm:us-east-2:123456789012:certificate/byo-default",
      "arn:aws:acm:us-east-2:123456789012:certificate/byo-extra",
    ]
  }

  assert {
    condition     = module.public_alb[0].https_listener_certificate_arn == ravion_aws_acm_certificate.cluster[0].arn
    error_message = "Managed mode must make the Ravion wildcard the default certificate"
  }

  assert {
    condition     = length(module.public_alb[0].additional_certificate_arns) == 2 && contains(module.public_alb[0].additional_certificate_arns, "arn:aws:acm:us-east-2:123456789012:certificate/byo-default") && contains(module.public_alb[0].additional_certificate_arns, "arn:aws:acm:us-east-2:123456789012:certificate/byo-extra")
    error_message = "Every BYO certificate must remain attached via SNI in managed mode"
  }
}

run "managed_private_uses_existing_listener" {
  command = plan

  variables {
    private_alb_creation_enabled = true
    private_alb_https_enabled    = true
    use_ravion_managed_domains   = true
    ravion_aws_account_id        = "aws_testaccount"
    ravion_cluster_name          = "platform"
  }

  assert {
    condition     = module.private_alb[0].https_listener_certificate_arn == ravion_aws_acm_certificate.cluster[0].arn
    error_message = "Managed mode must use the existing private ALB listener"
  }

  assert {
    condition     = ravion_aws_acm_certificate.cluster[0].target_dns_name == module.private_alb[0].alb_dns_name && ravion_aws_acm_certificate.cluster[0].target_zone_id == module.private_alb[0].alb_zone_id
    error_message = "The wildcard ALIAS target must be the selected private ALB"
  }

  assert {
    condition     = ravion_aws_acm_certificate.cluster[0].name == "platform"
    error_message = "ravion_cluster_name must override the wildcard leaf"
  }

  assert {
    condition     = output.private_alb_arn != null && output.private_alb_https_listener_arn != null && output.private_alb_security_group_id != null
    error_message = "The private ALB ARN, HTTPS listener ARN and security group id must be exposed for routing consumers"
  }
}

run "managed_domains_rejects_both_albs" {
  command = plan

  variables {
    public_alb_creation_enabled  = true
    public_alb_https_enabled     = true
    private_alb_creation_enabled = true
    private_alb_https_enabled    = true
    use_ravion_managed_domains   = true
    ravion_aws_account_id        = "aws_testaccount"
  }

  expect_failures = [ravion_aws_acm_certificate.cluster]
}

run "managed_domains_requires_https" {
  command = plan

  variables {
    public_alb_creation_enabled = true
    public_alb_https_enabled    = false
    use_ravion_managed_domains  = true
    ravion_aws_account_id       = "aws_testaccount"
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

run "managed_domains_requires_account_and_module_instance" {
  command = plan

  variables {
    public_alb_creation_enabled = true
    public_alb_https_enabled    = true
    use_ravion_managed_domains  = true
    module_instance_id          = null
  }

  expect_failures = [ravion_aws_acm_certificate.cluster]
}
