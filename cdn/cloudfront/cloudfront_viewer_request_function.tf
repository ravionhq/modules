resource "aws_cloudfront_function" "viewer_request" {
  count = local.viewer_request_function_enabled ? 1 : 0

  # Keep the physical name stable for distributions that already use redirects.
  name    = local.viewer_request_function_name
  runtime = "cloudfront-js-2.0"
  comment = "${var.name} viewer-request function"
  publish = true
  code    = local.viewer_request_function_code

  # Order distribution detachment before deleting the function.
  lifecycle {
    create_before_destroy = true

    precondition {
      condition     = length(local.viewer_request_function_code) <= 10240
      error_message = "The generated viewer-request function exceeds CloudFront Functions' 10 KB code limit. Reduce the number or length of redirect rules."
    }
  }
}

moved {
  from = aws_cloudfront_function.redirect
  to   = aws_cloudfront_function.viewer_request
}
