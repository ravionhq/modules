# Committed Lambda zip tests
# Run with: tofu init && tofu test
#
# lambda/alternat-lambda.zip must match what the pinned alterNAT release
# builds from its functions. Regenerate it after an alterNAT upgrade by
# copying the rebuilt zip this test writes into lambda/.

run "committed_zip_matches_alternat_functions" {
  command = apply

  module {
    source = "./tests/lambda_zip"
  }

  variables {
    source_dir  = ".terraform/modules/alternat/functions/replace-route"
    output_path = ".terraform/alternat-lambda-rebuilt.zip"
  }

  assert {
    condition     = output.output_base64sha256 == filebase64sha256("lambda/alternat-lambda.zip")
    error_message = "lambda/alternat-lambda.zip is out of date with the pinned alterNAT release. Copy .terraform/alternat-lambda-rebuilt.zip over it."
  }
}
