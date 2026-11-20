################################################################################
# Load balancer associations
#
# CloudFront distributions are not associated here: a distribution names its
# web ACL itself (web_acl_id), so pass the web_acl_arn output to it.
################################################################################

resource "aws_wafv2_web_acl_association" "alb" {
  for_each = var.target == "alb" ? toset(var.alb_arns) : toset([])

  region       = local.region
  resource_arn = each.value
  web_acl_arn  = aws_wafv2_web_acl.this.arn
}
