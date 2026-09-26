################################################################################
# Workload release teardown
#
# Ravion installs the workload's Helm release from the deploy path (a runner in
# the cluster VPC, or the cluster's Operator), not from Terraform. Destroying
# this stack has to remove that release all the same, otherwise the pods keep
# running against a target group, listener rule and image repository that are
# about to disappear, and Kubernetes finalizers end up waiting on cloud
# resources that are never coming back.
#
# This resource owns nothing while the stack is alive. Its only job is the
# destroy-time provisioner below, which runs `helm uninstall` on the release
# this stack was created for, BEFORE the resources it depends on are destroyed:
# Terraform destroys dependents first, so `depends_on` is what sequences the
# drain ahead of the target group, listener rule and repository.
#
# Everything the provisioner needs is captured in `input` at apply time and read
# back from state at destroy time, so a release is removed under the identity it
# was installed with even if the module's inputs changed since. `name` and
# `namespace` are immutable module inputs for the same reason.
#
# Cluster access follows the deploy path exactly: `aws eks get-token` with the
# cluster's `<cluster>-ravion-runner` role, which Ravion's Terraform runners
# may assume. The runner image ships `aws` but not `helm`, so a pinned helm is
# downloaded when none is on PATH; the archive is verified against the checksum
# published beside it.
################################################################################

resource "terraform_data" "workload_release" {
  count = local.workload_release_cleanup_enabled ? 1 : 0

  depends_on = [
    aws_lb_target_group.this,
    aws_lb_listener_rule.this,
    module.ecr,
  ]

  input = {
    region                 = local.region
    cluster_name           = var.cluster_name
    ravion_runner_role_arn = var.ravion_runner_role_arn
    release_name           = var.release_name
    release_namespace      = var.release_namespace
    helm_version           = var.workload_release_helm_version
    uninstall_timeout      = var.workload_release_uninstall_timeout
  }

  # A different release identity is a different release: replacing the resource
  # runs the destroy provisioner for the old name/namespace, which is the only
  # way the previous release gets removed when the identity is re-pointed.
  triggers_replace = {
    cluster_name      = var.cluster_name
    release_name      = var.release_name
    release_namespace = var.release_namespace
  }

  lifecycle {
    precondition {
      condition = alltrue([
        var.cluster_name != null,
        var.ravion_runner_role_arn != null,
        var.release_name != null,
        var.release_namespace != null,
      ])
      error_message = "workload_release_cleanup_enabled requires cluster_name, ravion_runner_role_arn, release_name and release_namespace."
    }
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/sh", "-c"]

    environment = {
      AWS_REGION             = self.input.region
      CLUSTER_NAME           = self.input.cluster_name
      RAVION_RUNNER_ROLE_ARN = self.input.ravion_runner_role_arn
      RELEASE_NAME           = self.input.release_name
      RELEASE_NAMESPACE      = self.input.release_namespace
      HELM_VERSION           = self.input.helm_version
      UNINSTALL_TIMEOUT      = self.input.uninstall_timeout
    }

    command = <<-EOT
      set -eu

      log() { echo "workload_release: $*"; }

      if ! command -v aws >/dev/null 2>&1; then
        echo "workload_release: the aws CLI is required to remove Helm release $RELEASE_NAME from cluster $CLUSTER_NAME" >&2
        exit 1
      fi

      # A cluster that no longer exists has no release to remove. This is the
      # ordinary case when the cluster stack was destroyed before the
      # workload stack, and it is a success: the release is gone.
      if ! aws eks describe-cluster --region "$AWS_REGION" --name "$CLUSTER_NAME" >/dev/null 2>&1; then
        log "cluster $CLUSTER_NAME is not reachable or no longer exists; nothing to uninstall"
        exit 0
      fi

      WORKDIR="$(mktemp -d)"
      trap 'rm -rf "$WORKDIR"' EXIT

      HELM="$(command -v helm 2>/dev/null || true)"
      if [ -z "$HELM" ]; then
        OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
        case "$(uname -m)" in
          x86_64|amd64) ARCH=amd64 ;;
          aarch64|arm64) ARCH=arm64 ;;
          *) echo "workload_release: unsupported architecture $(uname -m)" >&2; exit 1 ;;
        esac
        ARCHIVE="helm-$HELM_VERSION-$OS-$ARCH.tar.gz"
        log "helm not on PATH; downloading $ARCHIVE"
        curl -fsSL -o "$WORKDIR/$ARCHIVE" "https://get.helm.sh/$ARCHIVE"
        curl -fsSL -o "$WORKDIR/$ARCHIVE.sha256sum" "https://get.helm.sh/$ARCHIVE.sha256sum"
        (cd "$WORKDIR" && sha256sum -c "$ARCHIVE.sha256sum" >/dev/null)
        tar -xzf "$WORKDIR/$ARCHIVE" -C "$WORKDIR" "$OS-$ARCH/helm"
        HELM="$WORKDIR/$OS-$ARCH/helm"
      fi

      # Exec credential plugin: the token is minted by `aws eks get-token` each
      # time helm needs one and never lands on disk. The runner role is the
      # same one the deploy path assumes.
      KUBECONFIG="$WORKDIR/kubeconfig"
      aws eks update-kubeconfig \
        --region "$AWS_REGION" \
        --name "$CLUSTER_NAME" \
        --role-arn "$RAVION_RUNNER_ROLE_ARN" \
        --kubeconfig "$KUBECONFIG" >/dev/null
      export KUBECONFIG

      # --ignore-not-found makes a re-run of a partially completed destroy a
      # no-op rather than a failure. --wait holds until the workload's objects
      # are actually gone, so the target group is not deleted from under
      # pods that are still draining.
      log "uninstalling Helm release $RELEASE_NAME from namespace $RELEASE_NAMESPACE on $CLUSTER_NAME"
      "$HELM" uninstall "$RELEASE_NAME" \
        --namespace "$RELEASE_NAMESPACE" \
        --ignore-not-found \
        --wait \
        --timeout "$UNINSTALL_TIMEOUT"
      log "release $RELEASE_NAME removed"
    EOT
  }
}
