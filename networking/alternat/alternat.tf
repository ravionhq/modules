resource "terraform_data" "preconditions" {
  lifecycle {
    precondition {
      condition = alltrue([
        for subnet in concat(values(data.aws_subnet.public), values(data.aws_subnet.private)) : subnet.vpc_id == var.vpc_id
      ])
      error_message = "Every public and private subnet must belong to ${var.vpc_id}."
    }

    precondition {
      condition     = length(local.shared_route_table_ids) == 0
      error_message = "Route table(s) ${join(", ", sort(tolist(local.shared_route_table_ids)))} serve both public and private subnets. alterNAT would replace their Internet Gateway route and cut the NAT instances off from the internet. Give the private subnets their own route tables."
    }

    precondition {
      condition     = var.fallback_nat_gateway_id == null || try(data.aws_nat_gateway.fallback[0].connectivity_type, "public") == "public"
      error_message = "The fallback NAT gateway ${coalesce(var.fallback_nat_gateway_id, "-")} is private and cannot reach the internet. Choose a public NAT gateway."
    }

    precondition {
      condition     = contains(data.aws_ec2_instance_type.nat.supported_architectures, "arm64") || contains(data.aws_ec2_instance_type.nat.supported_architectures, "x86_64")
      error_message = "The NAT instance type ${var.nat_instance_type} must support the arm64 or x86_64 architecture."
    }

    precondition {
      condition     = length(var.nat_instance_eip_allocation_ids) == 0 || length(var.nat_instance_eip_allocation_ids) == length(local.nat_azs)
      error_message = "Provide exactly one Elastic IP allocation ID per NAT instance: this VPC gets ${length(local.nat_azs)} NAT instance(s), in ${join(", ", local.nat_azs)}."
    }

    precondition {
      condition     = !var.nat_restore_enabled || var.ssm_enabled
      error_message = "NAT restore runs its health check through Systems Manager, so it requires ssm_enabled."
    }

    precondition {
      condition     = var.fallback_nat_gateway_mode != "existing" || module.fallback.valid
      error_message = "${var.vpc_id} has ${module.fallback.error_message}"
    }
  }
}

module "alternat" {
  source  = "chime/alternat/aws"
  version = "0.10.4"

  vpc_id      = var.vpc_id
  vpc_az_maps = local.vpc_az_maps

  # NAT instances
  nat_instance_type     = var.nat_instance_type
  architecture          = local.architecture
  nat_ami               = var.nat_instance_ami_id == null ? "" : var.nat_instance_ami_id
  nat_instance_eip_ids  = var.nat_instance_eip_allocation_ids
  max_instance_lifetime = var.max_instance_lifetime_days * 86400
  nat_instance_key_name = var.nat_instance_key_name == null ? "" : var.nat_instance_key_name

  nat_instance_user_data_pre_install  = var.nat_instance_user_data_pre_install
  nat_instance_user_data_post_install = var.nat_instance_user_data_post_install

  # Encrypt the root volume. With the CloudWatch agent on the minimal AMI,
  # alterNAT sizes and encrypts the root volume itself.
  nat_instance_block_devices = var.cloudwatch_agent_enabled ? {} : {
    xvda = {
      device_name = "/dev/xvda"
      ebs = {
        encrypted   = true
        volume_type = "gp3"
      }
    }
  }

  ingress_security_group_ids              = var.allowed_security_group_ids
  ingress_security_group_cidr_blocks      = concat(local.vpc_ipv4_cidr_blocks, var.allowed_cidr_blocks)
  ingress_security_group_ipv6_cidr_blocks = local.vpc_ipv6_cidr_blocks

  enable_ssm              = var.ssm_enabled
  enable_cloudwatch_agent = var.cloudwatch_agent_enabled

  # Fallback NAT gateway
  create_nat_gateways             = var.fallback_nat_gateway_mode == "create"
  nat_gateway_id                  = local.fallback_nat_gateway_id
  fallback_ngw_eip_allocation_ids = var.fallback_nat_gateway_eip_allocation_ids
  enable_nat_restore              = var.nat_restore_enabled

  # Connectivity checks
  connectivity_test_check_urls = var.connectivity_check_urls

  # This module manages the EC2 endpoint itself (vpc_endpoints.tf), so the
  # endpoint does not depend on alterNAT's pinned terraform-aws-vpc release.
  enable_ec2_endpoint = false

  # Zip packaging builds the Lambdas from the module source, so no container
  # image has to be built and pushed. The functions only need boto3, which the
  # Python runtime provides.
  #
  # alterNAT writes the zip only when its archive_file resource is created, so
  # a saved plan applied on another machine finds no zip at a scratch path.
  # The zip is committed here instead: archive_file output is reproducible, so
  # it rewrites the same bytes, and tests/lambda_zip.tftest.hcl fails when an
  # alterNAT upgrade changes the functions.
  lambda_package_type           = "Zip"
  lambda_function_architectures = ["arm64"]
  lambda_zip_path               = "${path.module}/lambda/alternat-lambda.zip"
  lambda_has_ipv6               = length(local.vpc_ipv6_cidr_blocks) > 0

  # Names derived from var.name, so several instances of this module can share
  # an AWS account and region.
  autoscaling_hook_function_name        = local.autoscaling_hook_function_name
  connectivity_tester_function_name     = local.connectivity_tester_function_name
  connectivity_test_event_rule_name     = "${var.name}-connectivity-test"
  nat_instance_name_prefix              = "${var.name}-nat-"
  nat_instance_sg_name_prefix           = "${var.name}-nat-instance-"
  nat_instance_iam_role_name            = "${var.name}-nat-instance"
  nat_instance_iam_profile_name         = "${var.name}-nat-instance"
  nat_instance_lifecycle_hook_role_name = "${var.name}-nat-lifecycle-hook"
  nat_lambda_function_role_name         = "${var.name}-nat-lambda"

  tags = local.tags

  depends_on = [terraform_data.preconditions]
}
