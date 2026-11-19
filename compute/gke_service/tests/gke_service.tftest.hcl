mock_provider "google" {
  mock_resource "google_service_account" {
    defaults = {
      email  = "web-750a9b@test-project.iam.gserviceaccount.com"
      member = "serviceAccount:web-750a9b@test-project.iam.gserviceaccount.com"
      name   = "projects/test-project/serviceAccounts/web-750a9b@test-project.iam.gserviceaccount.com"
    }
  }
  mock_data "google_compute_subnetworks" {
    defaults = {
      subnetworks = [{
        description              = ""
        ip_cidr_range            = "10.129.0.0/23"
        name                     = "proxy-only"
        network                  = "default"
        network_name             = "default"
        network_self_link        = "https://www.googleapis.com/compute/v1/projects/test-project/global/networks/default"
        private_ip_google_access = false
        self_link                = "https://www.googleapis.com/compute/v1/projects/test-project/regions/us-central1/subnetworks/proxy-only"
        }, {
        description              = ""
        ip_cidr_range            = "10.200.0.0/23"
        name                     = "other-proxy-only"
        network                  = "other-vpc"
        network_name             = "other-vpc"
        network_self_link        = "https://www.googleapis.com/compute/v1/projects/test-project/global/networks/other-vpc"
        private_ip_google_access = false
        self_link                = "https://www.googleapis.com/compute/v1/projects/test-project/regions/us-central1/subnetworks/other-proxy-only"
      }]
    }
  }
  # The cluster's subnetwork, in the default network. The beta self link checks
  # that networks compare by path, not by API version.
  mock_data "google_compute_subnetwork" {
    defaults = {
      network = "https://www.googleapis.com/compute/beta/projects/test-project/global/networks/default"
    }
  }
  mock_resource "google_compute_global_address" {
    defaults = { address = "203.0.113.10" }
  }
  mock_resource "google_compute_address" {
    defaults = { address = "10.0.0.50" }
  }
}

variables {
  name              = "web"
  project_id        = "test-project"
  region            = "us-central1"
  release_name      = "web"
  release_namespace = "shop-prod"
}

run "workload_identity_grants_roles_to_a_google_service_account_of_this_stack" {
  command = plan

  variables {
    cluster_name                    = "gke-a"
    workload_identity_pool          = "test-project.svc.id.goog"
    workload_identity_project_roles = ["roles/storage.objectViewer", "roles/pubsub.subscriber"]
  }

  assert {
    condition     = toset(keys(google_project_iam_member.workload_identity)) == toset(["roles/storage.objectViewer", "roles/pubsub.subscriber"])
    error_message = "Each listed role must be granted once."
  }

  # sha256("gke-a/us-central1/shop-prod/web") starts with 750a9b.
  assert {
    condition     = google_service_account.workload_identity[0].account_id == "web-750a9b"
    error_message = "The Google service account ID must be the workload name plus a hash of the cluster, region, namespace and service account."
  }

  assert {
    condition     = google_service_account_iam_member.workload_identity[0].role == "roles/iam.workloadIdentityUser" && google_service_account_iam_member.workload_identity[0].member == "serviceAccount:test-project.svc.id.goog[shop-prod/web]"
    error_message = "Only the release's Kubernetes service account, named after the release, may act as the Google service account."
  }
}

# Every cluster in a project shares one Workload Identity pool, so a grant to
# the Kubernetes service account principal would be the same IAM member for the
# same namespace and release on another cluster, and destroying either stack
# would revoke both. Each stack must own a distinct Google service account.
run "another_cluster_with_the_same_release_gets_its_own_google_service_account" {
  command = plan

  variables {
    cluster_name                    = "gke-b"
    workload_identity_project_roles = ["roles/storage.objectViewer"]
  }

  # sha256("gke-b/us-central1/shop-prod/web") starts with 652118.
  assert {
    condition     = google_service_account.workload_identity[0].account_id == "web-652118"
    error_message = "A second cluster running the same namespace and release must get a different Google service account than gke-a (web-750a9b)."
  }
}

run "project_roles_name_the_google_service_account_not_the_kubernetes_principal" {
  command = plan

  variables {
    cluster_name                    = "gke-a"
    workload_identity_project_roles = ["roles/storage.objectViewer"]
  }

  assert {
    condition     = google_project_iam_member.workload_identity["roles/storage.objectViewer"].member == "serviceAccount:web-750a9b@test-project.iam.gserviceaccount.com"
    error_message = "Project roles must name this stack's Google service account, never the shared principal://.../subject/ns/<namespace>/sa/<name> principal."
  }

  assert {
    condition     = output.workload_identity_service_account_email == "web-750a9b@test-project.iam.gserviceaccount.com"
    error_message = "The email output is what the chart annotates the Kubernetes service account with."
  }
}

run "google_service_account_id_fits_30_characters_and_starts_with_a_letter" {
  command = plan

  variables {
    name                            = "1shop-production-web-frontend-extra"
    cluster_name                    = "gke-a"
    workload_identity_project_roles = ["roles/storage.objectViewer"]
  }

  assert {
    condition     = google_service_account.workload_identity[0].account_id == "w1shop-production-web-f-750a9b"
    error_message = "Long names are truncated to 30 characters, and names starting with a digit get a letter prefix."
  }
}

run "no_roles_means_no_identity" {
  command = plan

  assert {
    condition     = length(google_service_account.workload_identity) == 0 && length(google_project_iam_member.workload_identity) == 0 && output.workload_identity_service_account_email == null
    error_message = "Without roles no Google service account is created and nothing is granted."
  }
}

run "roles_require_a_namespace" {
  command = plan

  variables {
    cluster_name                    = "gke-a"
    release_namespace               = null
    workload_identity_project_roles = ["roles/storage.objectViewer"]
  }

  expect_failures = [var.workload_identity_project_roles]
}

run "roles_require_a_cluster" {
  command = plan

  variables {
    workload_identity_project_roles = ["roles/storage.objectViewer"]
  }

  expect_failures = [var.workload_identity_project_roles]
}

run "repository_only_for_built_images" {
  command = plan

  variables {
    artifact_registry_repository_creation_enabled = true
  }

  assert {
    condition     = google_artifact_registry_repository.this[0].repository_id == "web" && google_artifact_registry_repository.this[0].format == "DOCKER"
    error_message = "The repository defaults to the workload name."
  }

  assert {
    condition     = output.artifact_registry_repository_url == "us-central1-docker.pkg.dev/test-project/web/web"
    error_message = "The chart needs a full image path, not only the repository host."
  }
}

run "no_repository_for_registry_images" {
  command = plan

  assert {
    condition     = length(google_artifact_registry_repository.this) == 0 && output.artifact_registry_repository_url == null
    error_message = "No repository unless Ravion builds the image."
  }
}

run "external_gateway_reserves_a_global_address" {
  variables {
    load_balancer_scheme         = "external"
    hostnames                    = ["*.example.com", "shop.example.com"]
    gateway_certificate_map_name = "shop"
  }

  assert {
    condition     = length(google_compute_global_address.gateway) == 1 && length(google_compute_address.gateway) == 0
    error_message = "An external Gateway uses a global address."
  }

  assert {
    condition     = output.load_balancer_url == "https://shop.example.com"
    error_message = "The URL must use the first concrete hostname and https once a certificate is configured."
  }

  assert {
    condition     = join(",", output.load_balancer_source_cidr_blocks) == "130.211.0.0/22,35.191.0.0/16"
    error_message = "An external Gateway reaches pods from Google's front end ranges only."
  }
}

run "external_gateway_without_hostnames_uses_its_address" {
  variables {
    load_balancer_scheme = "external"
  }

  assert {
    condition     = output.load_balancer_url == "http://203.0.113.10"
    error_message = "Without hostnames or a certificate the URL is plain HTTP to the Gateway address."
  }
}

run "internal_gateway_admits_the_proxy_only_subnet" {
  variables {
    load_balancer_scheme = "internal"
    subnetwork           = "default"
  }

  assert {
    condition     = length(google_compute_address.gateway) == 1 && google_compute_address.gateway[0].address_type == "INTERNAL"
    error_message = "An internal Gateway uses an internal regional address."
  }

  assert {
    condition     = contains(output.load_balancer_source_cidr_blocks, "10.129.0.0/23") && !contains(output.load_balancer_source_cidr_blocks, "10.200.0.0/23")
    error_message = "A regional internal Gateway forwards from its own network's proxy-only subnet, which must be admitted; another VPC's must not."
  }
}

# A proxy-only subnet in another VPC of the region must not satisfy the
# precondition: the Gateway in the cluster's VPC could not be programmed.
run "internal_gateway_requires_a_proxy_only_subnet_in_its_own_network" {
  command = plan

  variables {
    load_balancer_scheme = "internal"
    subnetwork           = "projects/test-project/regions/us-central1/subnetworks/isolated-subnet"
  }

  override_data {
    target = data.google_compute_subnetwork.gateway
    values = {
      network = "https://www.googleapis.com/compute/v1/projects/test-project/global/networks/isolated"
    }
  }

  expect_failures = [google_compute_address.gateway]
}

run "cluster_only_has_no_load_balancer" {
  command = plan

  variables {
    kubernetes_service_enabled = true
    container_port             = 3000
  }

  assert {
    condition     = output.load_balancer_url == null && length(output.load_balancer_source_cidr_blocks) == 0 && length(google_compute_global_address.gateway) == 0
    error_message = "A cluster-only workload reserves no address."
  }

  assert {
    condition     = output.service_url == "http://web.shop-prod.svc.cluster.local:3000"
    error_message = "The in-cluster URL is derived from the release identity."
  }
}

run "release_cleanup_requires_cluster_access" {
  command = plan

  variables {
    workload_release_cleanup_enabled = true
  }

  expect_failures = [terraform_data.workload_release]
}
