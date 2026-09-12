################################################################################
# AWS Load Balancer Controller — Pod Identity Role
#
# Creates an IAM role trusted by the EKS Pod Identity service principal and
# associates it with the LB controller's service account. The Helm install of
# the controller itself is the consumer's responsibility.
################################################################################

module "lb_controller_role" {
  count = var.aws_load_balancer_controller_pod_identity_creation_enabled ? 1 : 0

  source = "../../../../security/iam"

  name        = "${var.name}-lb-controller"
  description = "AWS Load Balancer Controller Pod Identity role for ${var.name}"

  custom_assume_role_policy = local.pod_identity_trust_policy

  inline_policies = {
    "lb-controller" = file("${path.module}/policies/lb_controller.json")
  }

  tags = local.tags
}

resource "aws_eks_pod_identity_association" "lb_controller" {
  count = var.aws_load_balancer_controller_pod_identity_creation_enabled ? 1 : 0

  cluster_name    = aws_eks_cluster.this.name
  namespace       = var.aws_load_balancer_controller_namespace
  service_account = var.aws_load_balancer_controller_service_account
  role_arn        = module.lb_controller_role[0].role_arn

  tags = local.tags
}
