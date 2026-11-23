# Ravion GCP project setup. See README.md.
#
# Everything Ravion may do in the project comes from catalog.gen.tf.json,
# which is generated from Ravion's purpose catalog: one service account and one
# custom role per tier, and per-purpose impersonation bindings. Do not edit
# that file: Ravion regenerates it from the catalog, which is also what Ravion
# checks the project against.

locals {
  setup_version = trimspace(file("${path.module}/VERSION"))
  connection_id = var.ravion_account_id
  provider_id   = coalesce(var.provider_id, substr("ravion-${replace(lower(trimprefix(var.ravion_account_id, "gcpact_")), "/[^a-z0-9-]/", "")}", 0, 32))

  # Tiers whose custom role holds at least one permission.
  role_tiers = { for name, tier in local.ravion_catalog.tiers : name => tier if length(tier.permissions) > 0 }

  # One impersonation binding per (tier, purpose): a token for purpose P can
  # only impersonate the service account of P's tier.
  purpose_bindings = {
    for purpose, p in local.ravion_catalog.purposes : purpose => {
      tier    = p.tier
      purpose = purpose
    }
  }

  # roles/iam.serviceAccountUser for a tier on the attached service accounts
  # its purposes create VMs with (runner, sandbox-host). Never project-wide.
  act_as_bindings = merge([
    for tier_name, tier in local.ravion_catalog.tiers : {
      for attached in tier.act_as : "${tier_name}/${attached}" => {
        tier     = tier_name
        attached = attached
      }
    }
  ]...)

  caller_list = join(", ", [for c in var.allowed_callers : "'${c}'"])
}

data "google_project" "this" {
  project_id = var.project_id
}

resource "google_project_service" "apis" {
  for_each = var.enable_apis ? toset(var.apis) : toset([])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# ---- Workload identity federation -------------------------------------------

resource "google_iam_workload_identity_pool" "ravion" {
  project                   = var.project_id
  workload_identity_pool_id = var.pool_id
  display_name              = "Ravion"
  description               = "Ravion (${local.connection_id}), setup ${local.setup_version}"

  depends_on = [google_project_service.apis]
}

resource "google_iam_workload_identity_pool_provider" "ravion" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.ravion.workload_identity_pool_id
  workload_identity_pool_provider_id = local.provider_id
  display_name                       = "Ravion OIDC"
  description                        = "Tokens from ${var.issuer_uri} for Ravion connection ${local.connection_id}"

  # Ravion is a multi-tenant issuer: the condition only admits tokens minted
  # for this connection, with a subject consistent with its purpose claim,
  # from the Ravion services listed in allowed_callers.
  attribute_condition = join(" && ", [
    "assertion['rvn:connection'] == '${local.connection_id}'",
    "assertion.sub == 'rvn:gcp:${local.connection_id}:purpose:' + assertion['rvn:purpose']",
    "assertion['rvn:caller_service'] in [${local.caller_list}]",
  ])

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.connection" = "assertion['rvn:connection']"
    "attribute.purpose"    = "assertion['rvn:purpose']"
    "attribute.caller"     = "assertion['rvn:caller_service']"
  }

  oidc {
    issuer_uri = var.issuer_uri
    # No allowed_audiences: tokens must then carry this provider's full
    # resource name as aud, which Ravion sets per connection.
  }
}

# ---- Tier service accounts Ravion impersonates -------------------------------

resource "google_service_account" "tier" {
  for_each = local.ravion_catalog.tiers

  project      = var.project_id
  account_id   = each.value.account_id
  display_name = "Ravion ${each.key}"
  description  = each.value.description

  depends_on = [google_project_service.apis]
}

resource "google_project_iam_custom_role" "tier" {
  for_each = local.role_tiers

  project     = var.project_id
  role_id     = "ravion_${each.key}"
  title       = "Ravion ${each.key}"
  description = "Ravion ${each.key} tier, setup ${local.setup_version}: ${each.value.description}"
  stage       = "GA"
  permissions = each.value.permissions
}

resource "google_project_iam_member" "tier" {
  for_each = local.role_tiers

  project = var.project_id
  role    = google_project_iam_custom_role.tier[each.key].id
  member  = "serviceAccount:${google_service_account.tier[each.key].email}"
}

resource "google_service_account_iam_member" "workload_identity_user" {
  for_each = local.purpose_bindings

  service_account_id = google_service_account.tier[each.value.tier].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.ravion.name}/attribute.purpose/${each.value.purpose}"
}

# ---- Service accounts Ravion attaches to the VMs it creates -------------------

resource "google_service_account" "attached" {
  for_each = local.ravion_catalog.attached_service_accounts

  project      = var.project_id
  account_id   = each.value.account_id
  display_name = "Ravion ${each.key}"
  description  = each.value.description

  depends_on = [google_project_service.apis]
}

resource "google_project_iam_member" "runner" {
  for_each = toset(var.runner_sa_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.attached["runner"].email}"
}

resource "google_project_iam_member" "sandbox_host" {
  for_each = toset(var.sandbox_host_sa_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.attached["sandbox-host"].email}"
}

# Sandbox hosts mint their guests' credentials by impersonating ravion-runner
# (the step and session identity), so the host account may create its tokens.
resource "google_service_account_iam_member" "sandbox_host_impersonates_runner" {
  service_account_id = google_service_account.attached["runner"].name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${google_service_account.attached["sandbox-host"].email}"
}

resource "google_service_account_iam_member" "act_as" {
  for_each = local.act_as_bindings

  service_account_id = google_service_account.attached[each.value.attached].name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.tier[each.value.tier].email}"
}

# ---- Report the setup to Ravion ----------------------------------------------

locals {
  callback_body = jsonencode({
    ravion_account_id          = local.connection_id
    project_id                 = var.project_id
    project_number             = data.google_project.this.number
    workload_identity_provider = google_iam_workload_identity_pool_provider.ravion.name
    pool_id                    = google_iam_workload_identity_pool.ravion.workload_identity_pool_id
    provider_id                = google_iam_workload_identity_pool_provider.ravion.workload_identity_pool_provider_id
    issuer_uri                 = var.issuer_uri
    service_accounts           = { for name, sa in google_service_account.tier : name => sa.email }
    attached_service_accounts  = { for name, sa in google_service_account.attached : name => sa.email }
    setup_version              = local.setup_version
  })
}

# Runs again whenever the reported setup changes (an upgrade to a new VERSION,
# a re-created provider or service account). Ravion then verifies the
# connection itself (token exchange and testIamPermissions per tier) before
# marking it connected; IAM changes can take a few minutes to propagate, and
# Ravion retries verification.
resource "terraform_data" "callback" {
  count = var.send_callback ? 1 : 0

  triggers_replace = [local.callback_body]

  provisioner "local-exec" {
    command = "curl --fail-with-body --silent --show-error --retry 5 --retry-all-errors --retry-delay 5 -X POST \"$RAVION_CALLBACK_URL\" -H \"Authorization: Bearer $RAVION_ONBOARDING_TOKEN\" -H 'Content-Type: application/json' --data \"$RAVION_CALLBACK_BODY\""
    environment = {
      RAVION_CALLBACK_URL     = var.callback_url
      RAVION_CALLBACK_BODY    = local.callback_body
      RAVION_ONBOARDING_TOKEN = var.onboarding_token
    }
  }

  depends_on = [
    google_project_iam_member.tier,
    google_service_account_iam_member.workload_identity_user,
    google_service_account_iam_member.act_as,
    google_project_iam_member.runner,
    google_project_iam_member.sandbox_host,
  ]
}
