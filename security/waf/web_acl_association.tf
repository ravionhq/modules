################################################################################
# Load balancer associations
#
# CloudFront distributions are not associated here: a distribution names its
# web ACL itself (web_acl_id), so pass the web_acl_arn output to it.
################################################################################

# Keyed by position, not by ARN: an ALB created in the same plan has no ARN
# until apply, and for_each keys must be known when planning.
resource "aws_wafv2_web_acl_association" "alb" {
  for_each = var.target == "alb" ? { for index, arn in var.alb_arns : tostring(index) => arn } : {}

  region       = local.region
  resource_arn = each.value
  web_acl_arn  = aws_wafv2_web_acl.this.arn
}
