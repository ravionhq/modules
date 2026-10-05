# Basic Lambda Module Tests
# Run with: tofu test

mock_provider "aws" {
  override_resource {
    target = aws_lambda_function.this
    values = {
      arn           = "arn:aws:lambda:us-east-1:123456789012:function:test-lambda"
      invoke_arn    = "arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/test-lambda/invocations"
      qualified_arn = "arn:aws:lambda:us-east-1:123456789012:function:test-lambda:1"
      version       = "1"
      last_modified = "2026-01-01T00:00:00.000+0000"
    }
  }

  override_resource {
    target = aws_cloudwatch_log_group.this
    values = {
      arn = "arn:aws:logs:us-east-1:123456789012:log-group:/aws/lambda/test-lambda"
    }
  }

  override_resource {
    target = aws_lambda_function_url.this
    values = {
      function_url = "https://example.lambda-url.us-east-1.on.aws/"
    }
  }

  override_resource {
    target = aws_lambda_alias.this
    values = {
      arn = "arn:aws:lambda:us-east-1:123456789012:function:test-lambda:live"
    }
  }
}

variables {
  name                  = "test-lambda"
  package_type          = "Zip"
  runtime               = "nodejs24.x"
  handler               = "index.handler"
  s3_bucket             = "artifact-bucket"
  s3_key                = "lambda.zip"
  role_creation_enabled = false
  role_arn              = "arn:aws:iam::123456789012:role/existing-lambda-role"
}

run "basic_zip_function" {
  command = plan

  assert {
    condition     = aws_lambda_function.this.function_name == "test-lambda"
    error_message = "Lambda function name should match input."
  }

  assert {
    condition     = aws_lambda_function.this.package_type == "Zip"
    error_message = "Package type should be Zip."
  }

  assert {
    condition     = aws_lambda_function.this.runtime == "nodejs24.x"
    error_message = "Runtime should match input."
  }

  assert {
    condition     = length(aws_iam_role.this) == 0
    error_message = "IAM role should not be created when using an existing role."
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.this) == 1
    error_message = "CloudWatch log group should be created by default."
  }
}

run "existing_role_no_create" {
  command = plan

  variables {
    role_creation_enabled = false
    role_arn              = "arn:aws:iam::123456789012:role/existing-lambda-role-2"
  }

  assert {
    condition     = length(aws_iam_role.this) == 0
    error_message = "IAM role should not be created when role_creation_enabled is false."
  }
}

run "function_url_enabled" {
  command = plan

  variables {
    function_url_enabled   = true
    function_url_auth_type = "AWS_IAM"
  }

  assert {
    condition     = length(aws_lambda_function_url.this) == 1
    error_message = "Function URL should be created when enabled."
  }

  assert {
    condition     = aws_lambda_function_url.this[0].authorization_type == "AWS_IAM"
    error_message = "Function URL auth type should match input."
  }

  assert {
    condition     = aws_lambda_function_url.this[0].qualifier == "live" && aws_lambda_function.this.publish
    error_message = "The URL must invoke the deployment alias with version publishing enabled."
  }

  assert {
    condition     = length(aws_lambda_permission.function_url) == 0 && length(aws_lambda_permission.function_url_invoke) == 0
    error_message = "IAM-authenticated URLs must not grant public invoke permissions."
  }
}

run "public_function_url" {
  command = plan

  variables {
    function_url_enabled   = true
    function_url_auth_type = "NONE"
  }

  assert {
    condition     = aws_lambda_permission.function_url[0].qualifier == "live" && aws_lambda_permission.function_url[0].action == "lambda:InvokeFunctionUrl"
    error_message = "Public URL permission must be qualified to live."
  }

  assert {
    condition     = aws_lambda_permission.function_url_invoke[0].qualifier == "live" && aws_lambda_permission.function_url_invoke[0].invoked_via_function_url
    error_message = "Public invoke permission must be qualified and restricted to URL invocations."
  }
}

run "custom_url_permissions_follow_alias" {
  command = plan

  variables {
    function_url_enabled = true
    permissions = [{
      principal              = "123456789012"
      action                 = "lambda:InvokeFunctionUrl"
      function_url_auth_type = "AWS_IAM"
    }]
  }

  assert {
    condition     = aws_lambda_permission.this["0"].qualifier == "live"
    error_message = "Custom URL permissions must follow the deployment alias unless explicitly qualified."
  }
}

run "lambda_at_edge_valid_configuration" {
  command = plan

  variables {
    lambda_at_edge_enabled     = true
    version_publishing_enabled = true
    architecture               = "x86_64"
    timeout                    = 30
    memory_size                = 128
    environment_variables      = {}
    vpc_config                 = null
    layers                     = []
    file_system_configs        = []
    dead_letter_target_arn     = null
  }

  assert {
    condition     = aws_lambda_function.this.publish == true
    error_message = "Edge mode configuration should publish versions."
  }
}

run "image_registry_no_module_ecr" {
  command = plan

  variables {
    package_type                    = "Image"
    runtime                         = null
    handler                         = null
    s3_bucket                       = null
    s3_key                          = null
    ecr_repository_creation_enabled = false
    image_uri                       = "123456789012.dkr.ecr.us-east-1.amazonaws.com/my-function:v1"
  }

  assert {
    condition     = aws_lambda_function.this.package_type == "Image"
    error_message = "Package type should be Image."
  }

  assert {
    condition     = aws_lambda_function.this.image_uri == "123456789012.dkr.ecr.us-east-1.amazonaws.com/my-function:v1"
    error_message = "Function should be created from the external image URI."
  }

  assert {
    condition     = length(module.ecr) == 0
    error_message = "No module-owned ECR repository should be created for external image registries."
  }

  assert {
    condition     = length(terraform_data.bootstrap_image) == 0
    error_message = "No bootstrap image should be seeded when the image comes from an external registry."
  }
}

run "aliases_created" {
  command = plan

  variables {
    version_publishing_enabled = true
    aliases = {
      live = {
        function_version = "1"
      }
    }
  }

  assert {
    condition     = length(aws_lambda_alias.this) == 1
    error_message = "One alias should be created."
  }
}

# Keep mocked applies after plan-only runs so ignored function code does not
# leak a ZIP bootstrap state into the image creation test.
run "permissions_and_event_source_mappings" {
  command = apply

  variables {
    permissions = [
      {
        principal  = "events.amazonaws.com"
        source_arn = "arn:aws:events:us-east-1:123456789012:rule/test-rule"
      }
    ]
    event_source_mappings = [
      {
        event_source_arn = "arn:aws:sqs:us-east-1:123456789012:test-queue"
        batch_size       = 10
      }
    ]
  }

  assert {
    condition     = length(aws_lambda_permission.this) == 1
    error_message = "One lambda permission should be created."
  }

  assert {
    condition     = length(aws_lambda_event_source_mapping.this) == 1
    error_message = "One event source mapping should be created."
  }

  assert {
    condition     = aws_lambda_event_source_mapping.this["0"].function_name == aws_lambda_alias.this["live"].arn
    error_message = "Event source traffic must follow the live alias."
  }
}

run "apply_does_not_reset_alias_version" {
  command = plan

  variables {
    aliases = {
      live = {
        function_version = "2"
      }
    }
  }

  assert {
    condition     = aws_lambda_alias.this["live"].function_version == "1"
    error_message = "Terraform must preserve the live pointer after creation, even when configured differently."
  }
}
