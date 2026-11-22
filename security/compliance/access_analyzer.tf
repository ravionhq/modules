# One external-access analyzer per selected Region. It reports resource policies
# (S3, IAM roles, KMS, Lambda, Secrets Manager, SQS, SNS and others) that grant
# access to a principal outside this account. External-access analyzers are
# free, and an account may hold several, so an existing analyzer is left alone.
resource "aws_accessanalyzer_analyzer" "this" {
  for_each = var.access_analyzer_enabled ? local.regions : toset([])

  region = each.key

  analyzer_name = "account-external-access"
  type          = "ACCOUNT"

  tags = local.tags
}
