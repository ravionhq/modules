################################################################################
# Spot Interruption / Health Event Queue
#
# Karpenter consumes these events to gracefully drain doomed nodes before AWS
# reclaims them. Encryption at rest uses SQS-managed keys; HTTPS-only is
# enforced via the queue policy.
################################################################################

resource "aws_sqs_queue" "interruption" {
  name                      = local.queue_name
  message_retention_seconds = var.interruption_queue_message_retention_seconds
  sqs_managed_sse_enabled   = true

  tags = local.tags
}

data "aws_iam_policy_document" "interruption_queue" {
  statement {
    sid       = "EC2InterruptionPolicy"
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.interruption.arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "sqs.amazonaws.com"]
    }
  }

  statement {
    sid       = "DenyHTTP"
    effect    = "Deny"
    actions   = ["sqs:*"]
    resources = [aws_sqs_queue.interruption.arn]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_sqs_queue_policy" "interruption" {
  queue_url = aws_sqs_queue.interruption.id
  policy    = data.aws_iam_policy_document.interruption_queue.json
}
