terraform {
  required_version = ">= 1.10.0"

  cloud {}

  required_providers {
    planetscale = {
      source  = "planetscale/planetscale"
      version = "~> 1.11.0"
    }
  }
}
