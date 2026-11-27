terraform {
  required_version = ">= 1.10.0"

  cloud {}

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # 6.58 is the first release that accepts the nodejs26.x and python3.15 Lambda runtimes.
      version = ">= 6.58"
    }
  }
}
