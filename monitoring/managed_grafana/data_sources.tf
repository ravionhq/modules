################################################################################
# Grafana Data Sources
#
# Amazon Managed Grafana has no AWS API for data sources, so they are written
# through the workspace's Grafana API on apply, with a token minted for the
# run, after the catalog plugins they need are installed. The run repeats whenever the wanted data sources, the workspace or the
# script change. A data source removed by hand in Grafana comes back on the
# next change.
#
# The script also finds or creates the Grafana service account it signs in as.
# That account is not a Terraform resource: reading it needs
# grafana:ListWorkspaceServiceAccounts, which read-only plan credentials lack,
# so every plan after the first would fail refreshing it.
################################################################################

resource "terraform_data" "data_sources" {
  input = local.data_sources

  triggers_replace = {
    workspace_id    = aws_grafana_workspace.this.id
    service_account = local.service_account_name
    data_sources    = sha256(jsonencode(local.data_sources))
    plugins         = join(",", local.plugin_ids)
    script          = filesha256("${path.module}/scripts/provision_data_sources.py")
  }

  provisioner "local-exec" {
    interpreter = ["python3"]
    command     = "${path.module}/scripts/provision_data_sources.py"

    environment = {
      AWS_REGION      = local.region
      WORKSPACE_ID    = aws_grafana_workspace.this.id
      SERVICE_ACCOUNT = local.service_account_name
      GRAFANA_URL     = "https://${aws_grafana_workspace.this.endpoint}"
      DATA_SOURCES    = jsonencode(local.data_sources)
      MANAGED_UIDS    = jsonencode(local.managed_data_source_uids)
      PLUGIN_IDS      = jsonencode(local.plugin_ids)
    }
  }
}
