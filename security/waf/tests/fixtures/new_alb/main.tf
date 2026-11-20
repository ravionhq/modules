# An ALB created in the same plan as the web ACL: its ARN is unknown until
# apply, which for_each keys must not depend on.

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}
resource "aws_lb" "this" {
  name               = "new-alb"
  load_balancer_type = "application"
  subnets            = ["subnet-1", "subnet-2"]

  drop_invalid_header_fields = true
}

module "waf" {
  source = "../../.."

  name     = "new-alb-waf"
  target   = "alb"
  alb_arns = [aws_lb.this.arn]
}
