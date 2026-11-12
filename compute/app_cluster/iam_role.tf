################################################################################
# IAM Role and Instance Profile for the Router
#
# Ravion launches the router instance with this instance profile. The router
# publishes its request metrics to CloudWatch, in its own namespace only.
# Session Manager access for operators is added when ssm_enabled.
#
# The role and the instance profile share one name and the role has no path,
# so the role's ARN follows from the instance profile name that Ravion is
# handed when it launches the router.
################################################################################

resource "aws_iam_role" "router" {
  name = local.router_role_name
  path = "/"

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

# PutMetricData has no resource-level permissions: the namespace condition is
# the only scope it takes.
resource "aws_iam_role_policy" "router_metrics" {
  name = "publish-metrics"
  role = aws_iam_role.router.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = "cloudwatch:PutMetricData"
        Effect   = "Allow"
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = "Ravion/AppRouter"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "router_ssm" {
  count = var.ssm_enabled ? 1 : 0

  role       = aws_iam_role.router.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "router" {
  name = local.router_role_name
  role = aws_iam_role.router.name

  tags = local.tags
}
