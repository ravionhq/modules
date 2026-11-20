# GCE image module tests — run from module root: tofu test
# The component scripts themselves are run by test_component_scripts.py.

mock_provider "google" {
  mock_resource "google_service_account" {
    defaults = {
      email  = "app-image-builder@acme-images-1.iam.gserviceaccount.com"
      name   = "projects/acme-images-1/serviceAccounts/app-image-builder@acme-images-1.iam.gserviceaccount.com"
      member = "serviceAccount:app-image-builder@acme-images-1.iam.gserviceaccount.com"
    }
  }

  mock_resource "google_storage_bucket_object" {
    defaults = {
      generation = 1700000000000000
    }
  }

  override_data {
    target = data.google_compute_zones.available
    values = {
      names = ["us-central1-f", "us-central1-b", "us-central1-c"]
    }
  }

  override_data {
    target = data.google_compute_network.this
    values = {
      self_link = "https://www.googleapis.com/compute/v1/projects/acme-images-1/global/networks/default"
    }
  }

  override_data {
    target = data.google_compute_subnetwork.this
    values = {
      self_link = "https://www.googleapis.com/compute/v1/projects/acme-network/regions/us-central1/subnetworks/builds"
      network   = "https://www.googleapis.com/compute/v1/projects/acme-network/global/networks/shared"
    }
  }
}

variables {
  name       = "app-image"
  project_id = "acme-images-1"
  region     = "us-central1"
  components = [
    {
      name = "app"
      parameter_definitions = [
        { name = "Version", value = "v1.2.3" },
        { name = "Channel", default = "stable" },
        { name = "Blank", value = "  " },
      ]
      build_steps = [{ name = "Install", commands = ["echo install"] }]
    },
    {
      name       = "checks"
      test_steps = [{ name = "Runs", commands = ["app --version"], timeout_seconds = 600 }]
    },
  ]
}

run "defaults" {
  command = apply

  assert {
    condition     = output.zone == "us-central1-b"
    error_message = "Without a zone, builds should run in the first zone of the region that is up."
  }

  assert {
    condition     = google_service_account.builder.account_id == "app-image-builder"
    error_message = "A short name should name the builder service account <name>-builder."
  }

  assert {
    condition     = can(regex("^app-image-components-[0-9a-f]{8}$", google_storage_bucket.components.name))
    error_message = "The component bucket should be <name>-components-<project hash>."
  }

  assert {
    condition = (
      google_storage_bucket.components.uniform_bucket_level_access &&
      google_storage_bucket.components.public_access_prevention == "enforced" &&
      google_storage_bucket.components.versioning[0].enabled &&
      google_storage_bucket.components.location == "US-CENTRAL1"
    )
    error_message = "The component bucket should be private, versioned and in the region."
  }

  assert {
    condition     = one(google_storage_bucket.components.lifecycle_rule[0].condition).days_since_noncurrent_time == 30
    error_message = "Replaced component scripts should be kept for 30 days by default."
  }

  assert {
    condition     = [for ref in output.component_refs : ref.name] == ["app", "checks"]
    error_message = "component_refs should list the components in run order."
  }

  assert {
    condition     = can(regex("^gs://app-image-components-[0-9a-f]{8}/components/app-[0-9a-f]{16}\\.sh$", output.component_refs[0].url))
    error_message = "A component should be stored under a name made from its script's hash."
  }

  assert {
    condition     = output.component_refs[0].sha256 == sha256(google_storage_bucket_object.components["app"].content)
    error_message = "component_refs should carry the sha256 of the stored script."
  }

  assert {
    condition     = output.component_refs[0].parameters == { Version = "v1.2.3" }
    error_message = "Only parameters with a value should be passed by default; a blank value is unset."
  }

  assert {
    condition     = strcontains(local.component_scripts["checks"], "run_step 'Runs' 600 '${base64encode("app --version")}'")
    error_message = "A test step should run with its timeout."
  }

  assert {
    condition     = google_project_iam_member.builder_log_writer.role == "roles/logging.logWriter" && google_storage_bucket_iam_member.builder_components.role == "roles/storage.objectViewer"
    error_message = "The builder should write logs and read the component bucket."
  }

  assert {
    condition     = length(google_project_iam_member.builder) == 0 && length(google_storage_bucket_iam_member.builder_readers) == 0 && length(google_service_account_iam_member.deployers) == 0
    error_message = "No extra grants should be made by default."
  }

  assert {
    condition     = length(google_project_service.this) == 3
    error_message = "The Compute Engine, IAM and Cloud Storage APIs should be enabled by default."
  }

  assert {
    condition     = output.network_self_link == "https://www.googleapis.com/compute/v1/projects/acme-images-1/global/networks/default" && output.subnetwork_self_link == null
    error_message = "Without a subnetwork, builds should attach to the default network."
  }

  assert {
    condition     = output.labels["module"] == "compute-gce-image" && output.labels["managed-by"] == "terraform"
    error_message = "Images should carry the module's labels."
  }
}

run "objects_are_named_by_their_script" {
  command = plan

  assert {
    condition = alltrue([
      for name in ["app", "checks"] :
      google_storage_bucket_object.components[name].name == "components/${name}-${substr(sha256(google_storage_bucket_object.components[name].content), 0, 16)}.sh"
    ])
    error_message = "Each object should be named by its script's hash, so a changed component is a new object and an unchanged one keeps its own."
  }
}

run "long_name_and_grants" {
  command = plan

  variables {
    name                     = "a-very-long-image-builder-name"
    zone                     = "us-central1-c"
    subnetwork               = "builds"
    network_project_id       = "acme-network"
    builder_roles            = ["roles/artifactregistry.reader"]
    builder_bucket_readers   = ["acme-releases"]
    deployer_members         = ["serviceAccount:deployer@acme-images-1.iam.gserviceaccount.com"]
    component_retention_days = 7
    enable_project_services  = false
    labels                   = { "Team:Owner" = "Platform Team" }
  }

  assert {
    condition     = can(regex("^a-very-long-i-[0-9a-f]{7}-bld$", google_service_account.builder.account_id)) && length(google_service_account.builder.account_id) <= 30
    error_message = "A long name should be shortened with a hash to a valid service account id."
  }

  assert {
    condition     = output.zone == "us-central1-c"
    error_message = "A given zone should be used."
  }

  assert {
    condition = (
      output.subnetwork_self_link == "https://www.googleapis.com/compute/v1/projects/acme-network/regions/us-central1/subnetworks/builds" &&
      output.network_self_link == "https://www.googleapis.com/compute/v1/projects/acme-network/global/networks/shared"
    )
    error_message = "A Shared VPC subnetwork should be looked up in its own project."
  }

  assert {
    condition     = google_project_iam_member.builder["roles/artifactregistry.reader"].project == "acme-images-1"
    error_message = "Extra builder roles should be granted in the image project."
  }

  assert {
    condition     = google_storage_bucket_iam_member.builder_readers["acme-releases"].role == "roles/storage.objectViewer"
    error_message = "The builder should read the named buckets."
  }

  assert {
    condition     = google_service_account_iam_member.deployers["serviceAccount:deployer@acme-images-1.iam.gserviceaccount.com"].role == "roles/iam.serviceAccountUser"
    error_message = "Deployers should be able to act as the builder service account."
  }

  assert {
    condition     = one(google_storage_bucket.components.lifecycle_rule[0].condition).days_since_noncurrent_time == 7
    error_message = "component_retention_days should set how long replaced scripts are kept."
  }

  assert {
    condition     = length(google_project_service.this) == 0
    error_message = "enable_project_services = false should leave the APIs alone."
  }

  assert {
    condition     = local.labels["team-owner"] == "platform-team"
    error_message = "Labels should be rewritten into label syntax."
  }
}

run "rejects_a_component_without_steps" {
  command = plan

  variables {
    components = [{ name = "empty" }]
  }

  expect_failures = [var.components]
}

run "rejects_a_parameter_that_is_not_a_shell_name" {
  command = plan

  variables {
    components = [{
      name                  = "app"
      parameter_definitions = [{ name = "Release-Version" }]
      build_steps           = [{ name = "Install", commands = ["true"] }]
    }]
  }

  expect_failures = [var.components]
}

run "rejects_duplicate_components" {
  command = plan

  variables {
    components = [
      { name = "app", build_steps = [{ name = "A", commands = ["true"] }] },
      { name = "app", build_steps = [{ name = "B", commands = ["true"] }] },
    ]
  }

  expect_failures = [var.components]
}

run "rejects_duplicate_steps_in_a_phase" {
  command = plan

  variables {
    components = [{
      name        = "app"
      build_steps = [{ name = "A", commands = ["true"] }, { name = "A", commands = ["false"] }]
    }]
  }

  expect_failures = [var.components]
}

run "rejects_a_zone_outside_the_region" {
  command = plan

  variables {
    zone = "europe-west1-b"
  }

  expect_failures = [var.zone]
}
