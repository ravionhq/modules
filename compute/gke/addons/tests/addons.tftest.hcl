mock_provider "google" {
  mock_resource "google_service_account" {
    defaults = {
      email  = "test-cluster-eso@test-project.iam.gserviceaccount.com"
      member = "serviceAccount:test-cluster-eso@test-project.iam.gserviceaccount.com"
      name   = "projects/test-project/serviceAccounts/test-cluster-eso@test-project.iam.gserviceaccount.com"
    }
  }
  mock_data "google_container_cluster" {
    defaults = {
      endpoint = "10.0.0.2"
      control_plane_endpoints_config = [{
        dns_endpoint_config = [{
          endpoint                  = "gke-0123456789abcdef.us-central1.gke.goog"
          allow_external_traffic    = true
          enable_k8s_certs_via_dns  = false
          enable_k8s_tokens_via_dns = false
        }]
        ip_endpoints_config = [{ enabled = true }]
      }]
    }
  }
}

mock_provider "helm" {}

variables {
  cluster_name = "test-cluster"
  project_id   = "test-project"
  region       = "us-central1"
}

# Clusters in one project share a Workload Identity pool, so the grants must
# name a Google service account of this cluster: a principal shared with
# another cluster's stack would be revoked when either stack is destroyed.
run "eso_grants_belong_to_a_per_cluster_service_account" {
  command = plan

  variables {
    eso_enabled            = true
    eso_allowed_namespaces = ["web"]
  }

  assert {
    condition     = can(regex("^test-cluster-[0-9a-f]{6}-eso$", google_service_account.external_secrets[0].account_id))
    error_message = "The controller's Google service account ID must include a hash of the cluster name and region."
  }

  assert {
    condition     = google_project_iam_member.external_secrets[0].member == "serviceAccount:test-cluster-eso@test-project.iam.gserviceaccount.com"
    error_message = "Secret Manager access must go to the cluster's own Google service account."
  }

  assert {
    condition     = google_service_account_iam_member.external_secrets_workload_identity[0].member == "serviceAccount:test-project.svc.id.goog[external-secrets/external-secrets]"
    error_message = "The controller's Kubernetes service account must be allowed to act as the Google service account."
  }
}

run "eso_secret_ids_narrow_access_to_those_secrets" {
  command = plan

  variables {
    eso_enabled            = true
    eso_allowed_namespaces = ["web"]
    eso_secret_ids         = ["db-password", "projects/shared-project/secrets/api-key"]
  }

  assert {
    condition     = length(google_project_iam_member.external_secrets) == 0
    error_message = "Listing secrets must not also grant project-wide access."
  }

  assert {
    condition = toset(keys(google_secret_manager_secret_iam_member.external_secrets)) == toset([
      "projects/test-project/secrets/db-password",
      "projects/shared-project/secrets/api-key",
    ])
    error_message = "Bare secret IDs must resolve in the cluster project and full names must be kept."
  }
}

run "eso_store_requires_allowed_namespaces" {
  command = plan

  variables {
    eso_enabled = true
  }

  expect_failures = [helm_release.external_secrets_store]
}
