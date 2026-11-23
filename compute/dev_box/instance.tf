################################################################################
# Dev Box Instance
################################################################################

# Replaces the instance only when the image is chosen explicitly: a different
# custom AMI or operating system. New releases of the default image are
# ignored, so the box and its disk are never rebuilt behind the user's back.
resource "terraform_data" "image" {
  input = {
    ami_id           = var.ami_id
    operating_system = var.ami_id == null ? var.operating_system : null
  }
}

# Architecture the box was built for. It is recorded once and only refreshed
# when the box is rebuilt for a new image, so an instance type change to
# another architecture (x86 to Graviton) is refused instead of applied.
resource "terraform_data" "architecture" {
  input = local.cpu_architecture

  lifecycle {
    ignore_changes       = [input]
    replace_triggered_by = [terraform_data.image]
  }
}

resource "aws_instance" "this" {
  ami                         = local.ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_ids[0]
  vpc_security_group_ids      = concat([aws_security_group.this.id], var.additional_security_group_ids)
  iam_instance_profile        = aws_iam_instance_profile.instance.name
  associate_public_ip_address = var.public_ip_assignment_enabled
  key_name                    = var.key_name
  user_data                   = var.user_data != "" ? var.user_data : null
  disable_api_termination     = var.termination_protection_enabled

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = var.root_volume_type
    encrypted             = true
    kms_key_id            = var.root_volume_kms_key_id
    delete_on_termination = true
    tags                  = merge(local.tags, { Name = var.name })
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2 # Containers run on the box can reach IMDS.
    instance_metadata_tags      = "disabled"
  }

  tags = merge(local.tags, { Name = var.name })

  lifecycle {
    ignore_changes       = [ami, user_data, user_data_base64]
    replace_triggered_by = [terraform_data.image]

    precondition {
      condition     = local.cpu_architecture == terraform_data.architecture.output
      error_message = "Instance type ${var.instance_type} is ${local.cpu_architecture}, but this dev box was built for ${terraform_data.architecture.output}. Pick a ${terraform_data.architecture.output} instance type, or set a new ami_id or operating_system to rebuild the box (this erases its disk)."
    }
  }

  # Egress rules are separate resources; wait for them so the first boot
  # script has internet access.
  depends_on = [
    aws_iam_role_policy_attachment.ssm,
    aws_vpc_security_group_egress_rule.all_ipv4,
    aws_vpc_security_group_egress_rule.all_ipv6,
  ]
}
