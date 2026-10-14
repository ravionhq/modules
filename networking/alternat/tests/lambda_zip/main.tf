# Builds the alterNAT Lambda zip the way the pinned upstream module does
# (archive_file over functions/replace-route), for comparison with the zip
# committed in lambda/.

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.7.0"
    }
  }
}

variable "source_dir" {
  description = "alterNAT's functions/replace-route directory."
  type        = string
}

variable "output_path" {
  description = "Where to write the rebuilt zip."
  type        = string
}

data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = var.source_dir
  excludes    = ["__pycache__"]
  output_path = var.output_path
}

output "output_base64sha256" {
  value = data.archive_file.lambda.output_base64sha256
}
