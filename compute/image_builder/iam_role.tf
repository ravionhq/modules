################################################################################
# Build instance role
#
# The two AWS-managed policies are what Image Builder needs to drive a build
# instance; everything the components themselves reach is the caller's to grant
# through instance_managed_policy_arns and instance_policy_json.
################################################################################

locals {
  instance_managed_policy_arns = concat(
    [
      "arn:${data.aws_partition.current.partition}:iam::aws:policy/EC2InstanceProfileForImageBuilder",
      "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore",
    ],
    var.instance_managed_policy_arns,
  )
}

resource "aws_iam_role" "instance" {
  name        = "${var.name}-image-builder"
  description = "Build instance role for the ${var.name} Image Builder pipeline."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.${data.aws_partition.current.dns_suffix}" }
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "instance" {
  for_each = toset(local.instance_managed_policy_arns)

  role       = aws_iam_role.instance.name
  policy_arn = each.value
}

resource "aws_iam_role_policy" "instance" {
  count = var.instance_policy_json == null ? 0 : 1

  name   = "components"
  role   = aws_iam_role.instance.id
  policy = var.instance_policy_json
}

resource "aws_iam_role_policy" "logs" {
  count = var.log_bucket == null ? 0 : 1

  name = "build-logs"
  role = aws_iam_role.instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "s3:PutObject"
      Resource = "arn:${data.aws_partition.current.partition}:s3:::${var.log_bucket}/${local.log_prefix}/*"
    }]
  })
}

resource "aws_iam_instance_profile" "instance" {
  name = aws_iam_role.instance.name
  role = aws_iam_role.instance.name

  tags = local.tags
}
