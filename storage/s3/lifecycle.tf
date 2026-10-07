################################################################################
# S3 Bucket Lifecycle Configuration
################################################################################

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count = local.create_lifecycle_configuration ? 1 : 0

  region = var.region
  bucket = aws_s3_bucket.this.id

  dynamic "rule" {
    for_each = var.lifecycle_rules

    content {
      id     = rule.value.id
      status = rule.value.enabled ? "Enabled" : "Disabled"

      # Filter block - required by AWS
      # When tags are present, use 'and' block; otherwise use simple prefix filter
      dynamic "filter" {
        for_each = rule.value.tags == null || length(try(rule.value.tags, {})) == 0 ? [1] : []

        content {
          prefix = rule.value.prefix != null ? rule.value.prefix : ""
        }
      }

      dynamic "filter" {
        for_each = rule.value.tags != null && length(rule.value.tags) > 0 ? [1] : []

        content {
          and {
            prefix = rule.value.prefix != null ? rule.value.prefix : ""
            tags   = rule.value.tags
          }
        }
      }

      # Expiration settings for current versions
      dynamic "expiration" {
        for_each = rule.value.expiration != null ? [rule.value.expiration] : []

        content {
          days                         = expiration.value.days
          date                         = expiration.value.date
          expired_object_delete_marker = expiration.value.expired_object_delete_marker
        }
      }

      # Noncurrent version expiration
      dynamic "noncurrent_version_expiration" {
        for_each = rule.value.noncurrent_version_expiration != null ? [rule.value.noncurrent_version_expiration] : []

        content {
          noncurrent_days           = noncurrent_version_expiration.value.noncurrent_days
          newer_noncurrent_versions = noncurrent_version_expiration.value.newer_noncurrent_versions
        }
      }

      # Transitions to different storage classes
      dynamic "transition" {
        for_each = rule.value.transitions != null ? rule.value.transitions : []

        content {
          days          = transition.value.days
          date          = transition.value.date
          storage_class = transition.value.storage_class
        }
      }

      # Noncurrent version transitions
      dynamic "noncurrent_version_transition" {
        for_each = rule.value.noncurrent_version_transitions != null ? rule.value.noncurrent_version_transitions : []

        content {
          noncurrent_days           = noncurrent_version_transition.value.noncurrent_days
          newer_noncurrent_versions = noncurrent_version_transition.value.newer_noncurrent_versions
          storage_class             = noncurrent_version_transition.value.storage_class
        }
      }

      # Abort incomplete multipart uploads
      dynamic "abort_incomplete_multipart_upload" {
        for_each = rule.value.abort_incomplete_multipart_upload_days != null ? [rule.value.abort_incomplete_multipart_upload_days] : []

        content {
          days_after_initiation = abort_incomplete_multipart_upload.value
        }
      }
    }
  }
}
