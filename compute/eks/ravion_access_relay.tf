locals {
  ravion_access_name = "${substr(var.name, 0, 32)}-${substr(sha256(var.name), 0, 8)}-access"
  ravion_access_tags = merge(local.tags, {
    RavionPurpose    = "eks-access-relay"
    RavionClusterArn = module.cluster.cluster_arn
  })
}

data "aws_ssm_parameter" "ravion_access_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

data "aws_subnet" "ravion_access" {
  id = coalesce(var.ravion_access_relay_subnet_id, var.subnet_ids[0])
}

resource "aws_security_group" "ravion_access_relay" {
  name_prefix = "${local.ravion_access_name}-"
  description = "Outbound-only dedicated EKS SSM connection relay"
  vpc_id      = var.vpc_id
  tags        = local.ravion_access_tags
}

# SSM endpoints have no AWS-managed prefix list. Supply private endpoint CIDRs
# to restrict this further; otherwise HTTPS reaches SSM through existing NAT.
resource "aws_vpc_security_group_egress_rule" "ravion_access_https" {
  for_each          = toset(var.ravion_access_ssm_egress_cidrs)
  security_group_id = aws_security_group.ravion_access_relay.id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = each.value
  description       = "SSM HTTPS outbound"
  tags              = local.ravion_access_tags
}

resource "aws_vpc_security_group_egress_rule" "ravion_access_eks" {
  security_group_id            = aws_security_group.ravion_access_relay.id
  referenced_security_group_id = module.cluster.cluster_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  description                  = "EKS API HTTPS outbound"
  tags                         = local.ravion_access_tags
}

resource "aws_vpc_security_group_ingress_rule" "cluster_from_ravion_access" {
  security_group_id            = module.cluster.cluster_security_group_id
  referenced_security_group_id = aws_security_group.ravion_access_relay.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  description                  = "Dedicated SSM relay to EKS API"
  tags                         = local.ravion_access_tags
}

resource "aws_iam_role" "ravion_access_relay" {
  name = "${local.ravion_access_name}-relay"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow", Action = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
  tags = local.ravion_access_tags
}

resource "aws_iam_role_policy_attachment" "ravion_access_relay_ssm" {
  role       = aws_iam_role.ravion_access_relay.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ravion_access_relay" {
  name = "${local.ravion_access_name}-relay"
  role = aws_iam_role.ravion_access_relay.name
  tags = local.ravion_access_tags
}

resource "aws_instance" "ravion_access_relay" {
  ami                         = nonsensitive(data.aws_ssm_parameter.ravion_access_ami.value)
  instance_type               = var.ravion_access_relay_instance_type
  subnet_id                   = data.aws_subnet.ravion_access.id
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.ravion_access_relay.id]
  iam_instance_profile        = aws_iam_instance_profile.ravion_access_relay.name
  user_data                   = "#!/bin/bash\nset -eu\nsystemctl enable --now amazon-ssm-agent\nsystemctl disable --now sshd\n"
  user_data_replace_on_change = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    encrypted             = true
    delete_on_termination = true
    tags                  = local.ravion_access_tags
  }
  credit_specification {
    cpu_credits = "standard"
  }
  tags = merge(local.ravion_access_tags, {
    Name                  = "${var.name}-eks-access-relay"
    RavionSessionDocument = aws_ssm_document.ravion_access.name
    RavionAccessRoleArn   = aws_iam_role.ravion_access_admin.arn
    RavionReadRoleArn     = aws_iam_role.ravion_access_read.arn
  })

  depends_on = [aws_iam_role_policy_attachment.ravion_access_relay_ssm]

  lifecycle {
    precondition {
      condition     = var.endpoint_private_access_enabled
      error_message = "The dedicated access relay requires private EKS endpoint access."
    }
    precondition {
      condition     = data.aws_subnet.ravion_access.vpc_id == var.vpc_id && !data.aws_subnet.ravion_access.map_public_ip_on_launch && !contains(var.public_subnet_ids, data.aws_subnet.ravion_access.id)
      error_message = "The access relay subnet must be private and belong to the cluster VPC."
    }
  }
}

resource "aws_ssm_document" "ravion_access" {
  name            = "${local.ravion_access_name}-eks-api"
  document_type   = "Session"
  document_format = "JSON"
  content = jsonencode({
    schemaVersion = "1.0"
    description   = "Port forwarding exclusively to this cluster's EKS API"
    sessionType   = "Port"
    parameters = {
      localPortNumber = {
        type           = "String", default = "0"
        allowedPattern = "^([0-9]{1,4}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])$"
      }
    }
    properties = {
      type            = "LocalPortForwarding"
      host            = trimprefix(module.cluster.cluster_endpoint, "https://")
      portNumber      = "443"
      localPortNumber = "{{ localPortNumber }}"
    }
  })
  tags = local.ravion_access_tags
}
