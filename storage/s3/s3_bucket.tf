################################################################################
# S3 Bucket
################################################################################

resource "aws_s3_bucket" "this" {
  region        = var.region
  bucket        = var.name
  force_destroy = var.force_destroy_enabled

  tags = merge(local.tags, {
    Name = var.name
  })
}
