################################################################################
# S3 Bucket Policy
################################################################################

# Merge policy template statements with custom policy (if provided)
# The final policy combines:
# 1. Statements from selected policy templates (local.policy_template_statements)
# 2. Statements from custom_policy (if provided)
locals {
  # Parse custom policy statements if provided
  custom_policy_statements = var.custom_policy != null ? try(
    jsondecode(var.custom_policy).Statement,
    []
  ) : []

  # Combine all policy statements
  all_policy_statements = concat(
    local.policy_template_statements,
    local.custom_policy_statements
  )
}

resource "aws_s3_bucket_policy" "this" {
  count = local.create_bucket_policy ? 1 : 0

  region = var.region
  bucket = aws_s3_bucket.this.id

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = local.all_policy_statements
  })

  # Ensure public access block is created before bucket policy
  depends_on = [aws_s3_bucket_public_access_block.this]
}
