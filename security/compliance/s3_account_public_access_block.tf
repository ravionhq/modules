# The S3 account public access block is one setting for the whole account, not
# one per Region. It overrides every bucket's own setting, so the two halves are
# separate inputs: accounts that serve a bucket publicly by bucket policy can
# keep the ACL half and turn the policy half off.
resource "aws_s3_account_public_access_block" "this" {
  count = var.s3_public_acls_blocked || var.s3_public_policies_blocked ? 1 : 0

  block_public_acls       = var.s3_public_acls_blocked
  ignore_public_acls      = var.s3_public_acls_blocked
  block_public_policy     = var.s3_public_policies_blocked
  restrict_public_buckets = var.s3_public_policies_blocked
}
