provider "aws" {
  region = var.region
}

# Nothing to configure: base_url and api_key default to RAVION_BASE_URL and
# RAVION_API_KEY, which a Ravion pipeline injects for the run. Outside a
# pipeline, export both before applying.
provider "ravion" {}
