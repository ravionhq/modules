################################################################################
# Workload release teardown
#
# Ravion installs the workload's Helm release from the deploy path, not from
# Terraform. Destroying this stack has to remove that release all the same,
# otherwise the pods keep running and pulling from an image repository that is
# about to disappear, and keep an HTTPRoute attached to the shared Gateway.
#
# This resource owns nothing while the stack is alive. Its only job is the
# destroy-time provisioner below, which runs `helm uninstall` on the release
# this stack was created for, BEFORE the resources it depends on are
# destroyed: Terraform destroys dependents first.
#
# Everything the provisioner needs is captured in `input` at apply time and
# read back from state at destroy time, so a release is removed under the
# identity it was installed with even if the module's inputs changed since.
# No credential is stored: the provisioner mints a Google access token for the
# identity running the destroy (gcloud when installed, otherwise the metadata
# server of the runner VM), the same identity the GKE Add-ons stack uses, and
# sends it to the cluster's IAM-authorized DNS endpoint. The runner image
# ships neither helm nor gcloud reliably, so a pinned helm is downloaded when
# none is on PATH and verified against the checksum published beside it.
################################################################################

resource "terraform_data" "workload_release" {
  count = var.workload_release_cleanup_enabled ? 1 : 0

  # Destroyed first, so the release (and the web chart's Gateway, which holds
  # the reserved address through its forwarding rule) is gone before Terraform
  # deletes the address, the repository or the Workload Identity grants.
  depends_on = [
    google_artifact_registry_repository.this,
    google_compute_global_address.gateway,
    google_compute_address.gateway,
    google_service_account.workload_identity,
    google_service_account_iam_member.workload_identity,
    google_project_iam_member.workload_identity,
  ]

  input = {
    project_id        = var.project_id
    region            = var.region
    cluster_name      = var.cluster_name
    dns_endpoint      = var.dns_endpoint
    release_name      = var.release_name
    release_namespace = var.release_namespace
    helm_version      = var.workload_release_helm_version
    uninstall_timeout = var.workload_release_uninstall_timeout
  }

  # A different release identity is a different release: replacing the
  # resource runs the destroy provisioner for the old name/namespace.
  triggers_replace = {
    cluster_name      = var.cluster_name
    release_name      = var.release_name
    release_namespace = var.release_namespace
  }

  lifecycle {
    precondition {
      condition = alltrue([
        var.cluster_name != null,
        var.dns_endpoint != null,
        var.release_name != null,
        var.release_namespace != null,
      ])
      error_message = "workload_release_cleanup_enabled requires cluster_name, dns_endpoint, release_name and release_namespace."
    }
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/sh", "-c"]

    environment = {
      PROJECT_ID        = self.input.project_id
      REGION            = self.input.region
      CLUSTER_NAME      = self.input.cluster_name
      DNS_ENDPOINT      = self.input.dns_endpoint
      RELEASE_NAME      = self.input.release_name
      RELEASE_NAMESPACE = self.input.release_namespace
      HELM_VERSION      = self.input.helm_version
      UNINSTALL_TIMEOUT = self.input.uninstall_timeout
    }

    command = <<-EOT
      set -eu

      log() { echo "workload_release: $*"; }

      if command -v gcloud >/dev/null 2>&1; then
        TOKEN="$(gcloud auth print-access-token)"
      else
        TOKEN="$(curl -fsS -H 'Metadata-Flavor: Google' \
          'http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token' |
          sed -n 's/.*"access_token" *: *"\([^"]*\)".*/\1/p')"
      fi
      if [ -z "$TOKEN" ]; then
        echo "workload_release: no Google access token (install gcloud or run on a GCE runner) to remove Helm release $RELEASE_NAME from cluster $CLUSTER_NAME" >&2
        exit 1
      fi

      # A cluster that no longer exists has no release to remove. This is the
      # ordinary case when the cluster stack was destroyed before the
      # workload stack, and it is a success: the release is gone.
      STATUS="$(curl -sS -o /dev/null -w '%%{http_code}' -H "Authorization: Bearer $TOKEN" \
        "https://container.googleapis.com/v1/projects/$PROJECT_ID/locations/$REGION/clusters/$CLUSTER_NAME")"
      if [ "$STATUS" = "404" ]; then
        log "cluster $CLUSTER_NAME no longer exists; nothing to uninstall"
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

      # The DNS endpoint serves a publicly trusted certificate, so the
      # kubeconfig needs no cluster CA. The token is written only to this
      # temporary directory, which is removed on exit.
      KUBECONFIG="$WORKDIR/kubeconfig"
      umask 077
      cat >"$KUBECONFIG" <<KUBECONFIG_EOF
      apiVersion: v1
      kind: Config
      clusters:
        - name: gke
          cluster:
            server: https://$DNS_ENDPOINT
      users:
        - name: runner
          user:
            token: $TOKEN
      contexts:
        - name: gke
          context:
            cluster: gke
            user: runner
      current-context: gke
      KUBECONFIG_EOF
      export KUBECONFIG

      # --ignore-not-found makes a re-run of a partially completed destroy a
      # no-op rather than a failure. --wait holds until the workload's objects
      # are actually gone, so the repository is not deleted from under pods
      # that are still pulling from it.
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
