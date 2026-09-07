################################################################################
# Ravion Beacon (credential + Helm)
#
# Beacon is Ravion's in-cluster agent. It dials the control plane outbound over
# a single WebSocket — the control plane can never dial in, because a
# private-endpoint EKS API is reachable from nowhere else — and reports workload
# state. Deploying from inside the cluster is a separate, declined-by-default
# grant (beacon_deploy_enabled).
#
# Three things about the shape of this file:
#
#   1. THE CREDENTIAL IS A TERRAFORM RESOURCE. `ravion_operator_credential` mints
#      the WorkOS M2M client secret server-side and returns it exactly once, into
#      Terraform state. There is no API token to pass and no curl to run: the
#      provider authenticates with RAVION_API_KEY / RAVION_BASE_URL, which a
#      Ravion pipeline injects for the run.
#
#   2. EVERY ARGUMENT IS RequiresReplace, AND REPLACEMENT IS THE ROTATION. A
#      create for a cluster ARN that already has an agent mints a new secret and
#      the control plane revokes the previous one — there is no 409 and no
#      destroy-first dance, so a half-failed apply is simply retryable. The
#      resource has no update, no refresh (Read is a state passthrough, because
#      WorkOS cannot re-reveal a plaintext) and no import.
#
#   3. TERRAFORM ISSUES THE CREDENTIAL, NOT THE AGENT. Beacon only ever reads the
#      Kubernetes Secret and presents the pair over its existing WebSocket; the
#      gateway performs the WorkOS exchange server-side. That is what keeps
#      Beacon's RBAC free of every write verb and its egress down to one
#      destination. See docs/adr/beacon-workos-m2m-auth.md in the Ravion
#      monorepo.
#
# All releases set upgrade_install so an apply adopts a same-named release
# already present in the cluster instead of failing with "cannot re-use a name
# that is still in use".
################################################################################

locals {
  beacon_cluster_arn = data.aws_eks_cluster.this.arn
  beacon_region      = coalesce(var.region, data.aws_region.current.region)

  # Names and keys the two charts must agree on. Both ends are wired from these
  # locals rather than from the charts' defaults so they cannot drift apart.
  beacon_k8s_secret_name   = "ravion-beacon-credential"
  beacon_client_id_key     = "clientId"
  beacon_client_secret_key = "clientSecret"

  # Deterministic so an operator can find the mirror without consulting state.
  beacon_credential_secret_name = "ravion/beacon/${var.cluster_name}/credential"

  # The provider's namespace_scope is a set, and an absent one means cluster-wide
  # observation. An empty list is therefore sent as null rather than as an empty
  # set, so the recorded capability matches the RBAC the chart renders.
  beacon_capability_namespace_scope = length(var.beacon_namespace_scope) > 0 ? var.beacon_namespace_scope : null

  # An OCI reference names registry + chart in one string; the Helm provider
  # wants them split. A value that is not an OCI reference is treated as a
  # filesystem path to a chart directory, which is how the chart is tested
  # before it is published to ECR Public.
  beacon_chart_is_oci     = startswith(var.beacon_chart_source, "oci://")
  beacon_chart_repository = local.beacon_chart_is_oci ? regex("^(.*)/[^/]+$", var.beacon_chart_source)[0] : null
  beacon_chart_name       = local.beacon_chart_is_oci ? regex("^.*/([^/]+)$", var.beacon_chart_source)[0] : var.beacon_chart_source

  # The chart falls back to namespaceScope when deploy.namespaces is empty, so
  # the precondition below has to check the same fallback the chart will apply.
  beacon_deploy_namespaces_effective = length(var.beacon_deploy_namespaces) > 0 ? var.beacon_deploy_namespaces : var.beacon_namespace_scope
}

################################################################################
# Credential
#
# Ravion mints the client secret on the organization's shared WorkOS M2M
# application, records its id against this cluster's Beacon agent row, and
# returns the plaintext exactly once — into Terraform state, which from then on
# holds the only copy Ravion can never re-read.
#
# The provider reads RAVION_BASE_URL / RAVION_API_KEY from the environment; a
# Ravion pipeline injects both, and the organization comes from the key's claims.
# Neither an API token nor an API URL is a module input any more.
################################################################################

resource "ravion_operator_credential" "this" {
  count = var.beacon_enabled ? 1 : 0

  # cluster_name and region are derivable from the ARN, but both are passed
  # explicitly: this module already resolves them (region may be overridden by
  # var.region) and a mismatch is better caught here than inferred.
  cluster_arn  = local.beacon_cluster_arn
  cluster_name = var.cluster_name
  region       = local.beacon_region

  # Optional Ravion record ids. The control plane accepts the cluster identity
  # alone, so a null simply records nothing.
  project_id     = var.beacon_project_id
  environment_id = var.beacon_environment_id
  aws_account_id = var.beacon_aws_account_record_id

  # A nested attribute, not a block — note the `=`. Absent flags mean NOT
  # granted. These record on the agent what the chart below grants in the
  # cluster, so the two are driven from the same variables.
  capabilities = {
    exec_allowed        = var.beacon_exec_enabled
    self_update_allowed = var.beacon_self_update_enabled
    namespace_scope     = local.beacon_capability_namespace_scope
  }
}

################################################################################
# Credential mirror
#
# Terraform state now holds the credential; this Secrets Manager secret is the
# operator's recovery copy of it, in the customer's own account. It is a MIRROR,
# not an idempotency anchor: nothing reads it back, and the module no longer asks
# it "have we enrolled this cluster already?" — that whole mechanism belonged to
# the curl-era enrollment and is gone. Losing it costs nothing; losing state is
# recovered by replacing the credential resource, which mints a new secret and
# revokes the old one.
################################################################################

resource "aws_secretsmanager_secret" "beacon_credential" {
  count = var.beacon_enabled ? 1 : 0

  name        = local.beacon_credential_secret_name
  description = "Ravion Beacon WorkOS M2M credential mirror for EKS cluster ${var.cluster_name}. Operator recovery copy of what Terraform state holds."

  # No recovery window. The name is deterministic, so a 30-day window would
  # block re-enabling Beacon on this cluster for a month after disabling it —
  # and a revoked credential has no value worth recovering.
  recovery_window_in_days = 0

  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "beacon_credential" {
  count = var.beacon_enabled ? 1 : 0

  secret_id = aws_secretsmanager_secret.beacon_credential[0].id

  # Same two keys the Kubernetes Secret carries, so a value pasted from one is
  # readable in the other without reshaping.
  secret_string = jsonencode({
    (local.beacon_client_id_key)     = ravion_operator_credential.this[0].client_id
    (local.beacon_client_secret_key) = ravion_operator_credential.this[0].client_secret
  })
}

################################################################################
# Credential Secret
#
# Delivered as a local chart because the Helm provider is the only Kubernetes
# access this stack has, and because the beacon chart deliberately does not
# create this object: Beacon holds no RBAC on Secrets, so the kubelet reads it
# and projects it into the container.
################################################################################

resource "helm_release" "beacon_credential" {
  count = var.beacon_enabled ? 1 : 0

  name      = "ravion-beacon-credential"
  namespace = var.beacon_namespace
  chart     = "${path.module}/charts/beacon-credential"

  create_namespace = true
  upgrade_install  = true

  # sensitive() covers the whole document rather than the client secret alone:
  # this chart carries nothing that is worth showing in a plan, and marking the
  # element is what keeps the secret out of plan output and CI logs. Deliberately
  # not set_sensitive: Helm's `--set` parser splits on `,`, `.` and `=`, which
  # silently truncates a client secret containing any of them.
  values = [
    sensitive(yamlencode({
      secretName      = local.beacon_k8s_secret_name
      clientIdKey     = local.beacon_client_id_key
      clientSecretKey = local.beacon_client_secret_key
      clientId        = ravion_operator_credential.this[0].client_id
      clientSecret    = ravion_operator_credential.this[0].client_secret
    })),
  ]
}

################################################################################
# Beacon agent
################################################################################

resource "helm_release" "beacon" {
  count = var.beacon_enabled ? 1 : 0

  name       = "ravion-beacon"
  namespace  = var.beacon_namespace
  repository = local.beacon_chart_repository
  chart      = local.beacon_chart_name
  version    = var.beacon_chart_version

  upgrade_install = true

  values = concat(
    [
      yamlencode({
        # The chart refuses to render without all three.
        cluster = {
          arn    = local.beacon_cluster_arn
          name   = var.cluster_name
          region = local.beacon_region
        }
        controlPlane = {
          endpoint = var.beacon_endpoint
        }
        credential = {
          secretName      = local.beacon_k8s_secret_name
          clientIdKey     = local.beacon_client_id_key
          clientSecretKey = local.beacon_client_secret_key
        }
        # Empty is cluster-wide observation. Non-empty renders no ClusterRole at
        # all — one namespaced Role per entry instead — which is the difference
        # between a restriction Ravion promises and one Kubernetes enforces.
        namespaceScope = var.beacon_namespace_scope
        exec = {
          enabled = var.beacon_exec_enabled
        }
        selfUpdate = {
          enabled = var.beacon_self_update_enabled
        }
        # The widest grant this chart can create, and off by default. Bounded by
        # the namespace list, which Kubernetes enforces; there is deliberately
        # no cluster-wide posture, so an empty list with deploy on fails the
        # render rather than granting cluster-wide write. yamlencode produces a
        # genuine empty list here, avoiding the `--set deploy.namespaces={}`
        # trap that yields a list containing one empty string.
        deploy = {
          enabled    = var.beacon_deploy_enabled
          namespaces = var.beacon_deploy_namespaces
        }
      }),
    ],
    # The stores Beacon may proxy a dashboard query to, and the credentials it
    # may present doing it. Built in observability_beacon.tf, because what may
    # be reached is a property of the thing being reached.
    local.beacon_observability_proxy_values,
    var.beacon_helm_values,
  )

  # The agent VERSION is not this module's business. The control plane rolls
  # the fleet forward by patching Beacon's own Deployment (beacon ADR §6), and
  # the chart (>= 0.4.1, image.preserveOnUpgrade) re-emits the running image
  # — registry and tag — on every helm upgrade, so an apply — a values change,
  # a module release, a rerun — carries the chart's RBAC and wiring forward
  # without touching the version. The chart's appVersion is only the FLOOR a
  # fresh install starts from.
  #
  # `beacon_image_tag` is the one deliberate exception: an explicit pin. It is
  # a pin for exactly as long as it is configured — every apply re-asserts it,
  # a control-plane rollout in between included — and REMOVING it hands the
  # version back to the control plane, because the next apply then renders the
  # chart with no tag and the chart preserves whatever is running. It is NOT
  # ignored after the first apply: releases up to 0.8.3 did that
  # (`ignore_changes = [set]`, the original "floor, not a pin" design), which
  # froze the first tag ever applied into the state for good, so a cluster
  # that had once been given a since-retired tag was rolled back to it on
  # every upgrade — and wedged once that image could no longer start.
  set = var.beacon_image_tag == null ? [] : [
    {
      name  = "image.tag"
      value = var.beacon_image_tag
    },
  ]

  # The Secret must exist before the pod starts; it is mounted, not read
  # through the API, so a missing one is a container that never runs.
  depends_on = [helm_release.beacon_credential]

  lifecycle {
    precondition {
      condition     = !var.beacon_deploy_enabled || length(local.beacon_deploy_namespaces_effective) > 0
      error_message = "beacon_deploy_enabled is true but neither beacon_deploy_namespaces nor beacon_namespace_scope names a namespace. The chart refuses to render a cluster-wide deploy grant, by design: there is no 'deploy everywhere' posture, because the failure mode is an agent that can delete workloads in namespaces nobody meant to hand it."
    }
  }
}
