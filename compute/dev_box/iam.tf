################################################################################
# Instance IAM Role
################################################################################

resource "aws_iam_role" "instance" {
  name = "${var.name}-dev-box"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
      }
    ]
  })

  tags = local.tags
}

# Session Manager shell access with no SSH keys or open ports.
resource "aws_iam_role_policy_attachment" "ssm" {
  count = var.ssm_enabled ? 1 : 0

  role       = aws_iam_role.instance.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "additional" {
  for_each = toset(var.iam_policy_arns)

  role       = aws_iam_role.instance.name
  policy_arn = each.value
}

resource "aws_iam_instance_profile" "instance" {
  name = "${var.name}-dev-box"
  role = aws_iam_role.instance.name

  tags = local.tags
}
