################################################################################
# AWS Load Balancer Controller (optional add-on)
#
# Turns Ingress resources into Application Load Balancers and LoadBalancer
# Services into NLBs. The IAM role and Pod Identity association are created by
# the compute/eks cluster stack (on by default); this installs the controller
# chart wired to that service account. region and vpcId are set explicitly so
# the controller also works on nodes with restricted IMDS and on Fargate.
################################################################################

locals {
  # The controller is installed only when something needs it: any shared load
  # balancer (workload modules register pods into their target groups via
  # TargetGroupBinding, which only the controller reconciles), or an explicit
  # aws_load_balancer_controller_enabled opt-in for Ingress/LoadBalancer-resource use.
  lb_controller_install = (
    var.aws_load_balancer_controller_enabled ||
    var.public_alb_creation_enabled ||
    var.private_alb_creation_enabled ||
    var.public_nlb_creation_enabled ||
    var.private_nlb_creation_enabled
  )
}

# Read CRDs from the selected upstream chart, including version overrides.
# Rendering is client-only; it does not install anything or contact Kubernetes.
data "helm_template" "lb_controller" {
  count = local.lb_controller_install ? 1 : 0

  name       = "aws-load-balancer-controller"
  namespace  = var.aws_load_balancer_controller_namespace
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.aws_load_balancer_controller_chart_version

  include_crds = true
  values       = [yamlencode({ clusterName = var.cluster_name })]
}

# Helm never upgrades a chart's crds/ directory. This wrapper installs the
# selected chart's CRDs as templates with helm.sh/resource-policy: keep, so
# upgrades work but disabling/destroying the add-on preserves workload bindings.
# take_ownership adopts CRDs created by an earlier controller installation.
resource "helm_release" "lb_controller_crds" {
  count = local.lb_controller_install ? 1 : 0

  name      = "aws-load-balancer-controller-crds"
  namespace = var.aws_load_balancer_controller_namespace
  chart     = "${path.module}/charts/aws-load-balancer-controller-crds"
  # The Helm provider does not read a local chart's version at plan time, so a
  # wrapper version bump planned the old version and failed the apply with an
  # inconsistent result. Pin it to Chart.yaml so the plan sees the bump.
  version = yamldecode(file("${path.module}/charts/aws-load-balancer-controller-crds/Chart.yaml")).version

  create_namespace = true
  upgrade_install  = true
  take_ownership   = true

  values = [yamlencode({ crds = data.helm_template.lb_controller[0].crds })]
}

resource "helm_release" "lb_controller" {
  count = local.lb_controller_install ? 1 : 0

  name       = "aws-load-balancer-controller"
  namespace  = var.aws_load_balancer_controller_namespace
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.aws_load_balancer_controller_chart_version

  # Adopt a same-named release already in the cluster (e.g. left behind by a
  # deleted module instance) instead of failing on install.
  upgrade_install = true
  skip_crds       = true

  values = concat(
    [
      yamlencode({
        clusterName = var.cluster_name
        region      = data.aws_region.current.region
        vpcId       = data.aws_eks_cluster.this.vpc_config[0].vpc_id
        # Must match the Pod Identity association created by the compute/eks
        # stack, or the controller falls back to the node role and fails.
        serviceAccount = {
          create = true
          name   = var.aws_load_balancer_controller_service_account
        }
        # How often a TargetGroupBinding re-reads target health while a pod
        # waits on its load balancer readiness gate. The controller's 15-second
        # default can hold a healthy pod unready for most of that interval,
        # which every rolling deploy pays; it only polls while a gate is open.
        targetgroupbindingRequeueDuration = "2s"
      }),
    ],
    local.addon_placement_values,
    var.aws_load_balancer_controller_helm_values,
  )

  depends_on = [helm_release.lb_controller_crds]
}
