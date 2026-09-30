################################################################################
# Grafana Data Sources
#
# Amazon Managed Grafana has no AWS API for data sources, so they are written
# through the workspace's Grafana API on apply, with a token minted for the
# run. The run repeats whenever the wanted data sources, the workspace or the
# script change. A data source removed by hand in Grafana comes back on the
# next change.
################################################################################

resource "terraform_data" "data_sources" {
  input = local.data_sources

  triggers_replace = {
    workspace_id       = aws_grafana_workspace.this.id
    service_account_id = aws_grafana_workspace_service_account.provisioner.service_account_id
    data_sources       = sha256(jsonencode(local.data_sources))
    script             = filesha256("${path.module}/scripts/provision_data_sources.py")
  }

  provisioner "local-exec" {
    interpreter = ["python3"]
    command     = "${path.module}/scripts/provision_data_sources.py"

    environment = {
      AWS_REGION         = local.region
      WORKSPACE_ID       = aws_grafana_workspace.this.id
      SERVICE_ACCOUNT_ID = aws_grafana_workspace_service_account.provisioner.service_account_id
      GRAFANA_URL        = "https://${aws_grafana_workspace.this.endpoint}"
      DATA_SOURCES       = jsonencode(local.data_sources)
      MANAGED_UIDS       = jsonencode(local.managed_data_source_uids)
    }
  }
}
