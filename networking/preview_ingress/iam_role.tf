################################################################################
# IAM Role for the Router Instance
#
# The router needs no AWS permission to do its work. The role exists only so
# operators can open a Session Manager shell, and is absent when that is off.
################################################################################

resource "aws_iam_role" "router" {
  count = var.ssm_enabled ? 1 : 0

  name = local.router_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "router_ssm" {
  count = var.ssm_enabled ? 1 : 0

  role       = aws_iam_role.router[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "router" {
  count = var.ssm_enabled ? 1 : 0

  name = local.router_name
  role = aws_iam_role.router[0].name

  tags = local.tags
}
