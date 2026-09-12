################################################################################
# EventBridge Rules → Interruption Queue
#
# These mirror the rules in the upstream Karpenter CloudFormation. Each rule
# fans out a specific EC2 / Health event class into the interruption queue
# for Karpenter to consume.
################################################################################

locals {
  interruption_event_rules = {
    scheduled_change = {
      description = "AWS Health scheduled change events for Karpenter."
      source      = ["aws.health"]
      detail_type = ["AWS Health Event"]
    }
    spot_interruption = {
      description = "EC2 Spot Instance Interruption Warnings for Karpenter."
      source      = ["aws.ec2"]
      detail_type = ["EC2 Spot Instance Interruption Warning"]
    }
    rebalance_recommendation = {
      description = "EC2 Instance Rebalance Recommendations for Karpenter."
      source      = ["aws.ec2"]
      detail_type = ["EC2 Instance Rebalance Recommendation"]
    }
    instance_state_change = {
      description = "EC2 Instance State-change Notifications for Karpenter."
      source      = ["aws.ec2"]
      detail_type = ["EC2 Instance State-change Notification"]
    }
    capacity_reservation_interruption = {
      description = "EC2 Capacity Reservation Instance Interruption Warnings for Karpenter."
      source      = ["aws.ec2"]
      detail_type = ["EC2 Capacity Reservation Instance Interruption Warning"]
    }
  }
}

resource "aws_cloudwatch_event_rule" "this" {
  for_each = local.interruption_event_rules

  name        = "${local.queue_name}-${each.key}"
  description = each.value.description

  event_pattern = jsonencode({
    source      = each.value.source
    detail-type = each.value.detail_type
  })

  tags = local.tags
}

resource "aws_cloudwatch_event_target" "this" {
  for_each = local.interruption_event_rules

  rule      = aws_cloudwatch_event_rule.this[each.key].name
  target_id = "KarpenterInterruptionQueueTarget"
  arn       = aws_sqs_queue.interruption.arn
}
