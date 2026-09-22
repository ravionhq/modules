variable "regions" {
  type        = list(string)
  description = "AWS Regions where all private ECR repositories scan images on push. Each Region must be enabled for the account."
  nullable    = false

  validation {
    condition     = length(var.regions) > 0
    error_message = "At least one Region is required."
  }

  validation {
    condition     = alltrue([for region in var.regions : can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", region))])
    error_message = "Every entry in regions must be an AWS Region code such as us-east-1 or eu-central-1."
  }

  validation {
    condition     = length(var.regions) == length(distinct(var.regions))
    error_message = "Regions must not contain duplicates."
  }
}
