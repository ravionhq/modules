################################################################################
# S3 Bucket Request Payment Configuration
################################################################################

# Created only for Requester Pays: a bucket owner paying is S3's default, and
# destroying this resource puts the bucket back to it.
resource "aws_s3_bucket_request_payment_configuration" "this" {
  count = var.requester_pays_enabled ? 1 : 0

  region = var.region
  bucket = aws_s3_bucket.this.id
  payer  = "Requester"
}
