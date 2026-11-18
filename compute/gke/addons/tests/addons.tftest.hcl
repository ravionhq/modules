mock_provider "google" {
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
  mock_data "google_project" {
    defaults = { number = "123456789012" }
  }
}

mock_provider "helm" {}

variables {
  cluster_name = "test-cluster"
  project_id   = "test-project"
  region       = "us-central1"
}

run "eso_principal_is_the_controller_service_account" {
  command = plan

  variables {
    eso_enabled            = true
    eso_allowed_namespaces = ["web"]
  }

  assert {
    condition     = google_project_iam_member.external_secrets[0].member == "principal://iam.googleapis.com/projects/123456789012/locations/global/workloadIdentityPools/test-project.svc.id.goog/subject/ns/external-secrets/sa/external-secrets"
    error_message = "Secret Manager access must go to the controller's own Kubernetes service account."
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
