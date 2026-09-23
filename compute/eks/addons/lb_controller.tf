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

# CRDs ship from a local chart because Helm never upgrades a chart's crds/
# directory, which would leave an upgraded controller on the CRDs of whichever
# version first installed it. The chart is a verbatim copy of the upstream
# crds/crds.yaml for the default controller version. take_ownership adopts CRDs
# an earlier controller install created outside any release.
resource "helm_release" "lb_controller_crds" {
  count = local.lb_controller_install ? 1 : 0

  name      = "aws-load-balancer-controller-crds"
  namespace = var.aws_load_balancer_controller_namespace
  chart     = "${path.module}/charts/aws-load-balancer-controller-crds"

  create_namespace = true
  upgrade_install  = true
  take_ownership   = true
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
    var.aws_load_balancer_controller_helm_values,
  )

  depends_on = [helm_release.lb_controller_crds]
}
