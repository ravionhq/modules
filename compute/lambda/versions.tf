terraform {
  required_version = ">= 1.10.0"

  cloud {}

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # 6.19 is the first release that accepts the nodejs24.x Lambda runtime.
      version = ">= 6.19"
    }
  }
}
