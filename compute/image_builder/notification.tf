################################################################################
# Build notification
#
# A pipeline that finishes a build says so on the default event bus. Forwarding
# that to an endpoint is what lets a system react to a new image without
# polling for one, and it is the only way to learn about a build nobody
# started from a deploy: a schedule, or a rebuild triggered by a new parent
# image.
#
# The event is forwarded whole. Its detail carries the image's ARN, and the
# receiver reads whatever else it needs back from Image Builder, because the
# event is a notification and the API is the record.
################################################################################

resource "aws_cloudwatch_event_connection" "notify" {
  count = local.notify_enabled ? 1 : 0

  region             = local.region
  name               = local.notify_names.connection
  description        = "Authorises ${var.name} build notifications"
  authorization_type = "API_KEY"

  auth_parameters {
    api_key {
      key   = var.notify_header_name
      value = local.notify_header_value
    }
  }
}

resource "aws_cloudwatch_event_api_destination" "notify" {
  count = local.notify_enabled ? 1 : 0

  region                           = local.region
  name                             = local.notify_names.destination
  description                      = "Where ${var.name} build notifications go"
  invocation_endpoint              = var.notify_url
  http_method                      = "POST"
  invocation_rate_limit_per_second = 10
  connection_arn                   = aws_cloudwatch_event_connection.notify[0].arn
}

# Only this pipeline's images, and only once they are finished. A build that is
# still running or has failed produced no image to tell anyone about, and every
# other pipeline in the account is somebody else's business.
#
# Image Builder names an image after the recipe it came from, lowercased, so
# the prefix names this recipe in full and ends at the separator the version
# follows. Stopping at the pipeline name instead would also match a pipeline
# whose name starts with this one: a rule for "app" would forward "app-prod"
# images. The recipe moves whenever its content does, and the rule moves with
# it in the same apply, so an image still building against the previous recipe
# when that happens finishes unannounced.
resource "aws_cloudwatch_event_rule" "notify" {
  count = local.notify_enabled ? 1 : 0

  region      = local.region
  name        = local.notify_names.rule
  description = "A ${var.name} image finished building and distributing"

  event_pattern = jsonencode({
    source        = ["aws.imagebuilder"]
    "detail-type" = ["EC2 Image Builder Image State Change"]
    detail = {
      state = { status = ["AVAILABLE"] }
    }
    resources = [{ prefix = "arn:${data.aws_partition.current.partition}:imagebuilder:${local.region}:${data.aws_caller_identity.current.account_id}:image/${lower(aws_imagebuilder_image_recipe.this.name)}/" }]
  })

  tags = local.tags
}

resource "aws_cloudwatch_event_target" "notify" {
  count = local.notify_enabled ? 1 : 0

  region   = local.region
  rule     = aws_cloudwatch_event_rule.notify[0].name
  arn      = aws_cloudwatch_event_api_destination.notify[0].arn
  role_arn = aws_iam_role.notify[0].arn

  # A delivery that fails is retried for an hour and then dropped rather than
  # retried forever, because an image that nobody could be told about is a
  # thing to alarm on, not to keep replaying.
  retry_policy {
    maximum_event_age_in_seconds = 3600
    maximum_retry_attempts       = 10
  }
}

resource "aws_iam_role" "notify" {
  count = local.notify_enabled ? 1 : 0

  name        = local.notify_names.role
  description = "Lets EventBridge deliver ${var.name} build notifications"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.tags
}

# The role can invoke this destination and nothing else.
resource "aws_iam_role_policy" "notify" {
  count = local.notify_enabled ? 1 : 0

  name = "invoke-destination"
  role = aws_iam_role.notify[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "events:InvokeApiDestination"
      Resource = aws_cloudwatch_event_api_destination.notify[0].arn
    }]
  })
}
